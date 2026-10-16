// deno test polls/
// The JPEG encoder against an independent decoder (jpeg-js): sizes, quality,
// 4:2:0 headers, the ICC round trip, and the EXIF orientation reader.
import assert from "node:assert/strict";
import jpeg from "npm:jpeg-js@0.4.4";
import { encodeJpeg, exifOrientation, iccProfile, scaledTable } from "./jpeg.ts";
import { gradient, makeJpeg, pixels, withExif } from "./test_images.ts";

function psnr(a: Uint8Array, b: Uint8Array): number {
  let squared = 0;
  let count = 0;
  for (let i = 0; i < a.length; i += 4) {
    for (let c = 0; c < 3; c++) {
      const d = a[i + c] - b[i + c];
      squared += d * d;
      count++;
    }
  }
  return squared === 0 ? Infinity : 10 * Math.log10((255 * 255) / (squared / count));
}

const decode = (bytes: Uint8Array) => jpeg.decode(bytes, { useTArray: true, formatAsRGBA: true });

/** The segments before the image data, in order: [marker, offset of the marker]. */
function segments(bytes: Uint8Array): [number, number][] {
  const found: [number, number][] = [];
  let i = 2;
  while (i + 4 <= bytes.length && bytes[i] === 0xff) {
    const marker = bytes[i + 1];
    found.push([marker, i]);
    if (marker === 0xda) break;
    i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
  }
  return found;
}
const markers = (bytes: Uint8Array) => segments(bytes).map(([marker]) => marker);

Deno.test("encodes a picture an independent decoder reads back closely", () => {
  for (const [width, height] of [[720, 540], [37, 23], [1, 1], [16, 16], [17, 9], [8, 33]]) {
    // Smooth, like a photo; 4:2:0 halves colour detail, so steep colour ramps would score lower.
    const source = pixels(width, height, (x, y) => [
      Math.round(120 + 60 * Math.sin(x / 7)),
      Math.round(120 + 60 * Math.cos(y / 5)),
      Math.round(140 + 40 * Math.sin((x + y) / 11)),
    ]);
    const bytes = encodeJpeg(source, width, height, { quality: 80 });
    const decoded = decode(bytes);
    assert.equal(decoded.width, width);
    assert.equal(decoded.height, height);
    assert.ok(psnr(source, decoded.data) > 34, `${width}×${height}: ${psnr(source, decoded.data).toFixed(1)} dB`);
  }
});

Deno.test("flat colours survive 4:2:0 exactly enough, edges included", () => {
  const width = 40;
  const height = 24;
  const source = pixels(width, height, (x) => x < 20 ? [247, 193, 217] : [18, 18, 18]);
  const decoded = decode(encodeJpeg(source, width, height, { quality: 90 }));
  const at = (x: number, y: number) => Array.from(decoded.data.subarray((y * width + x) * 4, (y * width + x) * 4 + 3));
  for (const [x, y, expected] of [[2, 2, [247, 193, 217]], [37, 20, [18, 18, 18]]] as const) {
    at(x, y).forEach((value, c) => assert.ok(Math.abs(value - expected[c]) <= 6, `${x},${y}: ${at(x, y)}`));
  }
});

Deno.test("baseline 4:2:0 with JFIF, nothing else unless a profile is given", () => {
  const bytes = makeJpeg(64, 48);
  assert.deepEqual(markers(bytes), [0xe0, 0xdb, 0xc0, 0xc4, 0xda]);
  const sof = segments(bytes).find(([marker]) => marker === 0xc0)![1];
  // 8 bits, 48 × 64, then Y 2×2 with table 0, Cb and Cr 1×1 with table 1.
  assert.deepEqual(Array.from(bytes.subarray(sof + 4, sof + 10)), [8, 0, 48, 0, 64, 3]);
  assert.deepEqual(Array.from(bytes.subarray(sof + 10, sof + 19)), [1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]);
  assert.deepEqual(Array.from(bytes.subarray(bytes.length - 2)), [0xff, 0xd9]);
  assert.equal(iccProfile(bytes), undefined);
});

Deno.test("quality scales the tables like libjpeg, and costs bytes", () => {
  assert.equal(scaledTable([16], 50)[0], 16);
  assert.equal(scaledTable([16], 75)[0], 8);
  assert.equal(scaledTable([16], 100)[0], 1);
  assert.equal(scaledTable([99], 10)[0], 255);
  const source = pixels(96, 96, (x, y) => [(x * 37 + y * 11) % 256, (x * 7 + y * 53) % 256, (x * y) % 256]);
  const low = encodeJpeg(source, 96, 96, { quality: 40 });
  const high = encodeJpeg(source, 96, 96, { quality: 95 });
  assert.ok(high.length > low.length * 1.5, `${low.length} → ${high.length}`);
  assert.ok(decode(high).width === 96 && decode(low).width === 96);
});

Deno.test("an ICC profile goes along, split over segments when it's large", () => {
  for (const size of [536, 70_000]) {
    const icc = Uint8Array.from({ length: size }, (_, i) => (i * 31) % 251);
    const bytes = encodeJpeg(gradient(32, 32), 32, 32, { icc });
    assert.deepEqual(iccProfile(bytes, 100_000), icc);
    assert.equal(iccProfile(bytes, 500), undefined, "too large for the caller's limit");
    assert.equal(decode(bytes).width, 32);
  }
});

Deno.test("reads the EXIF orientation in both byte orders, 1 when there's none", () => {
  const plain = makeJpeg(8, 8);
  assert.equal(exifOrientation(plain), 1);
  for (const orientation of [1, 3, 6, 8]) {
    assert.equal(exifOrientation(withExif(plain, orientation, false)), orientation);
    assert.equal(exifOrientation(withExif(plain, orientation, true)), orientation);
  }
  assert.equal(exifOrientation(withExif(plain, 9)), 1, "out of range");
  assert.equal(exifOrientation(new Uint8Array([0xff, 0xd8, 0xff])), 1, "truncated");
  assert.equal(exifOrientation(new Uint8Array([1, 2, 3, 4])), 1, "not a JPEG");
  assert.equal(decode(withExif(plain, 6)).width, 8, "still a valid JPEG");
});

Deno.test("rejects sizes it can't encode", () => {
  assert.throws(() => encodeJpeg(new Uint8Array(4), 0, 1));
  assert.throws(() => encodeJpeg(new Uint8Array(4), 2, 2));
});
