// deno test polls/
// A poll picture's way: what the contract accepts before admission, then
// decoding, orientation, flattening, shrinking and re-encoding without EXIF.
import assert from "node:assert/strict";
import jpeg from "npm:jpeg-js@0.4.4";
import { exifOrientation, iccProfile } from "./jpeg.ts";
import {
  base64,
  fittedSize,
  flattenOnWhite,
  MAX_PICTURE_BYTES,
  orient,
  preparePicture,
  type Screened,
  screenPicture,
  shrink,
} from "./picture.ts";
import { encodeJpeg } from "./jpeg.ts";
import { jpegUri, makeJpeg, makePng, pixels, pngUri, withExif, withFrameSize } from "./test_images.ts";

const decode = (bytes: Uint8Array) => jpeg.decode(bytes, { useTArray: true, formatAsRGBA: true });

function screened(uri: string): Screened {
  const result = screenPicture(uri);
  assert.ok(result.ok, JSON.stringify(result));
  return result;
}

async function prepared(uri: string) {
  const result = await preparePicture(screened(uri));
  assert.ok(result.ok, JSON.stringify(result));
  return result.picture;
}

const near = (actual: ArrayLike<number>, expected: number[], tolerance = 12) =>
  expected.every((value, i) => Math.abs(actual[i] - value) <= tolerance);

Deno.test("accepts JPEG and PNG data URIs within 1.5 MB, 4,096 px and 6 MP", () => {
  assert.ok(screenPicture(jpegUri(makeJpeg(40, 30))).ok);
  // Only the header is read here: 2,400 × 2,400 is 5.76 MP.
  const big = screenPicture(jpegUri(withFrameSize(makeJpeg(8, 8), 2400, 2400)));
  assert.equal(big.ok ? "ok" : big.code, "ok");
  const png = screenPicture(pngUri(
    new Uint8Array([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0,
      0,
      0,
      13,
      0x49,
      0x48,
      0x44,
      0x52,
      0,
      0,
      0,
      32,
      0,
      0,
      0,
      32,
      8,
      2,
    ]),
  ));
  assert.ok(png.ok && png.info.type === "png");
});

Deno.test("refuses other types, unreadable data and pictures over the limits", () => {
  const refused = (value: unknown) => {
    const result = screenPicture(value);
    return result.ok ? "ok" : result.code;
  };
  assert.equal(refused(42), "image_invalid");
  assert.equal(refused("https://example.com/picture.jpg"), "image_invalid");
  assert.equal(refused("data:image/jpeg;base64,!!!!"), "image_invalid");
  // WebP and HEIC aren't accepted (the app sends JPEG).
  const webp = new Uint8Array(40);
  webp.set([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x58]);
  webp.set([0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 9, 0, 0], 16);
  assert.equal(refused(`data:image/webp;base64,${base64(webp)}`), "image_invalid");
  // A JPEG labelled PNG.
  assert.equal(refused(`data:image/png;base64,${base64(makeJpeg(32, 32))}`), "image_invalid");
  // Over 1.5 MB: a valid JPEG header with filler after it.
  const padded = new Uint8Array(MAX_PICTURE_BYTES + 3);
  padded.set(makeJpeg(32, 32));
  assert.equal(refused(jpegUri(padded)), "too_large");
  // Over 6 MP (2,500 × 2,500) or 4,096 px, from the header alone.
  assert.equal(refused(jpegUri(withFrameSize(makeJpeg(8, 8), 2500, 2500))), "too_large");
  assert.equal(refused(jpegUri(withFrameSize(makeJpeg(8, 8), 4097, 16))), "image_invalid", "input.ts refuses 4,097 px");
  assert.equal(refused(jpegUri(withFrameSize(makeJpeg(8, 8), 4096, 1000))), "ok", "4,096 px wide is the edge");
});

Deno.test("shrinks to 720 px on the long side, never enlarges", async () => {
  const wide = await prepared(jpegUri(makeJpeg(1440, 960)));
  assert.deepEqual([wide.width, wide.height], [720, 480]);
  assert.deepEqual([decode(wide.jpeg).width, decode(wide.jpeg).height], [720, 480]);
  const small = await prepared(jpegUri(makeJpeg(300, 200)));
  assert.deepEqual([small.width, small.height], [300, 200]);
  assert.deepEqual(fittedSize(4000, 3000), { width: 720, height: 540 });
  assert.deepEqual(fittedSize(10, 5000), { width: 1, height: 720 });
});

Deno.test("turns an EXIF-rotated photo upright and drops every bit of EXIF", async () => {
  // Stored landscape, red on the left half; orientation 6 means "rotate 90° clockwise to view".
  const stored = pixels(64, 32, (x) => x < 32 ? [230, 20, 20] : [20, 20, 230]);
  const bytes = withExif(encodeJpeg(stored, 64, 32, { quality: 95 }), 6);
  assert.equal(exifOrientation(bytes), 6);
  const picture = await prepared(jpegUri(bytes));
  assert.deepEqual([picture.width, picture.height], [32, 64], "upright: portrait");
  const out = decode(picture.jpeg);
  // After a clockwise turn, the stored left half (red) is on top.
  assert.ok(near(out.data.subarray((4 * 32 + 16) * 4), [230, 20, 20]), "red on top");
  assert.ok(near(out.data.subarray((60 * 32 + 16) * 4), [20, 20, 230]), "blue below");
  assert.equal(exifOrientation(picture.jpeg), 1, "no orientation left");
  const text = new TextDecoder("latin1").decode(picture.jpeg);
  assert.ok(!text.includes("Exif") && !text.includes("GPS"), "no EXIF segment, no tags");
});

Deno.test("keeps the colour profile of a JPEG and of a PNG", async () => {
  const icc = Uint8Array.from({ length: 536 }, (_, i) => (i * 7) % 256);
  const fromJpeg = await prepared(jpegUri(encodeJpeg(pixels(16, 16, () => [1, 2, 3]), 16, 16, { icc })));
  assert.deepEqual(iccProfile(fromJpeg.jpeg), icc);
  const fromPng = await prepared(
    pngUri(await makePng({ width: 16, height: 16, colorType: 2, depth: 8, sample: () => [9, 9, 9], icc })),
  );
  assert.deepEqual(iccProfile(fromPng.jpeg), icc);
});

Deno.test("a transparent PNG lands on white, and its text chunks are gone", async () => {
  const png = await makePng({
    width: 40,
    height: 20,
    colorType: 6,
    depth: 8,
    sample: (x) => x < 20 ? [0, 0, 0, 0] : [0, 0, 0, 255],
  });
  const picture = await prepared(pngUri(png));
  const out = decode(picture.jpeg);
  assert.ok(near(out.data.subarray((10 * 40 + 4) * 4), [255, 255, 255]), "transparent → white");
  assert.ok(near(out.data.subarray((10 * 40 + 35) * 4), [0, 0, 0]), "opaque black stays");
  assert.ok(!new TextDecoder("latin1").decode(picture.jpeg).includes("private text"), "no tEXt");
});

Deno.test("a broken picture is image_invalid, never a crash", async () => {
  // A JPEG whose header is fine but whose data is cut short.
  const whole = makeJpeg(64, 64);
  const cut = whole.slice(0, Math.floor(whole.length * 0.6));
  const result = await preparePicture(screened(jpegUri(cut)));
  // jpeg-js decodes what it can of a truncated file (tolerantly) or refuses it: either way, no throw.
  assert.ok(result.ok || result.code === "image_invalid");
  const png = await makePng({ width: 16, height: 16, colorType: 2, depth: 8, sample: (x, y) => [x * 9, y * 13, 77] });
  const corrupt = png.slice();
  corrupt.fill(0x55, png.length - 40, png.length - 14); // inside the compressed data
  const broken = await preparePicture(screened(pngUri(corrupt)));
  assert.equal(broken.ok ? "ok" : broken.code, "image_invalid");
});

Deno.test("pixel helpers: area averaging, orientations, flattening", () => {
  const checker = { data: pixels(4, 4, (x, y) => (x + y) % 2 ? [255, 255, 255] : [0, 0, 0]), width: 4, height: 4 };
  const half = shrink(checker, 2, 2);
  for (let i = 0; i < 4; i++) {
    assert.ok(near(half.data.subarray(i * 4), [128, 128, 128], 1), "a 2×2 checker averages to grey");
  }

  // A 3×2 picture whose pixels name their place: orientations map them as EXIF says.
  const src = { data: pixels(3, 2, (x, y) => [x, y, 0]), width: 3, height: 2 };
  const at = (
    p: { data: Uint8Array; width: number },
    x: number,
    y: number,
  ) => [p.data[(y * p.width + x) * 4], p.data[(y * p.width + x) * 4 + 1]];
  const topLeft = (orientation: number) => at(orient(src, orientation), 0, 0);
  assert.deepEqual(topLeft(1), [0, 0]);
  assert.deepEqual(topLeft(2), [2, 0]);
  assert.deepEqual(topLeft(3), [2, 1]);
  assert.deepEqual(topLeft(4), [0, 1]);
  assert.deepEqual(topLeft(5), [0, 0]);
  assert.deepEqual(topLeft(6), [0, 1]);
  assert.deepEqual(topLeft(7), [2, 1]);
  assert.deepEqual(topLeft(8), [2, 0]);
  assert.deepEqual([orient(src, 6).width, orient(src, 6).height], [2, 3]);
  assert.deepEqual(at(orient(src, 6), 1, 0), [0, 0], "clockwise: the stored top-left ends up top-right");

  const translucent = Uint8Array.from([100, 200, 0, 128, 0, 0, 0, 0, 10, 20, 30, 255]);
  flattenOnWhite(translucent);
  assert.deepEqual(Array.from(translucent), [177, 227, 127, 255, 255, 255, 255, 255, 10, 20, 30, 255]);
});
