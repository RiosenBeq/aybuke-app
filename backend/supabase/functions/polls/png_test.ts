// deno test polls/
// The PNG decoder: every colour type and bit depth, all five filters, Adam7,
// palette and tRNS transparency, the iCCP profile, and files it must refuse.
import assert from "node:assert/strict";
import { decodePng, inflate, PngError } from "./png.ts";
import { makePng, type PngSpec, zlib } from "./test_images.ts";

const limits = { maxSide: 4096, maxPixels: 6_000_000 };

function rgbaAt(data: Uint8Array, width: number, x: number, y: number): number[] {
  const i = (y * width + x) * 4;
  return Array.from(data.subarray(i, i + 4));
}

/** Decodes the spec's PNG and compares every pixel with `expected`. */
async function check(spec: PngSpec, expected: (x: number, y: number) => number[]) {
  const image = await decodePng(await makePng(spec), limits);
  assert.equal(image.width, spec.width);
  assert.equal(image.height, spec.height);
  for (let y = 0; y < spec.height; y++) {
    for (let x = 0; x < spec.width; x++) {
      assert.deepEqual(
        rgbaAt(image.data, spec.width, x, y),
        expected(x, y),
        `${JSON.stringify(spec.colorType)} at ${x},${y}`,
      );
    }
  }
  return image;
}

const r = (x: number, y: number) => (x * 29 + y * 7) % 256;
const g = (x: number, y: number) => (x * 3 + y * 41) % 256;
const b = (x: number, y: number) => (x * y + 17) % 256;

Deno.test("RGBA 8-bit through all five filters, plain and interlaced", async () => {
  for (const interlace of [false, true]) {
    const image = await check(
      {
        width: 13,
        height: 11,
        colorType: 6,
        depth: 8,
        interlace,
        sample: (x, y) => [r(x, y), g(x, y), b(x, y), (x * 20) % 256],
      },
      (x, y) => [r(x, y), g(x, y), b(x, y), (x * 20) % 256],
    );
    assert.ok(image.hasAlpha);
  }
});

Deno.test("RGB 16-bit keeps the high byte; opaque", async () => {
  const image = await check(
    {
      width: 9,
      height: 7,
      colorType: 2,
      depth: 16,
      sample: (x, y) => [r(x, y) * 257, g(x, y) * 256 + 255, b(x, y) * 256],
    },
    (x, y) => [r(x, y), g(x, y), b(x, y), 255],
  );
  assert.equal(image.hasAlpha, false);
});

Deno.test("grey at 1, 2, 4 and 8 bits, scaled to 8 bits, with tRNS", async () => {
  for (const depth of [1, 2, 4, 8] as const) {
    const max = (1 << depth) - 1;
    const value = (x: number, y: number) => (x + y * 3) % (max + 1);
    await check(
      {
        width: 11,
        height: 5,
        colorType: 0,
        depth,
        interlace: depth === 2,
        sample: (x, y) => [value(x, y)],
        transparency: [0, max], // the brightest grey is transparent
      },
      (x, y) => {
        const v = Math.round(value(x, y) * (255 / max));
        return [v, v, v, value(x, y) === max ? 0 : 255];
      },
    );
  }
});

Deno.test("grey with alpha, 8 and 16 bits", async () => {
  await check(
    { width: 6, height: 6, colorType: 4, depth: 8, sample: (x, y) => [r(x, y), (y * 40) % 256] },
    (x, y) => [r(x, y), r(x, y), r(x, y), (y * 40) % 256],
  );
  await check(
    { width: 5, height: 3, colorType: 4, depth: 16, sample: (x, y) => [r(x, y) * 257, 65535] },
    (x, y) => [r(x, y), r(x, y), r(x, y), 255],
  );
});

Deno.test("palettes at 1, 2, 4 and 8 bits with palette alpha", async () => {
  const palette = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [247, 193, 217]];
  for (const depth of [2, 4, 8] as const) {
    const index = (x: number, y: number) => (x + y) % 4;
    await check(
      { width: 10, height: 4, colorType: 3, depth, sample: (x, y) => [index(x, y)], palette, transparency: [255, 128] },
      (x, y) => [...palette[index(x, y)], index(x, y) === 1 ? 128 : 255],
    );
  }
  await check(
    { width: 9, height: 2, colorType: 3, depth: 1, sample: (x) => [x % 2], palette: palette.slice(0, 2) },
    (x) => [...palette[x % 2], 255],
  );
});

Deno.test("RGB with a tRNS colour key", async () => {
  await check(
    {
      width: 4,
      height: 4,
      colorType: 2,
      depth: 8,
      sample: (x, y) => x === y ? [10, 20, 30] : [200, 100, 50],
      transparency: [0, 10, 0, 20, 0, 30],
    },
    (x, y) => x === y ? [10, 20, 30, 0] : [200, 100, 50, 255],
  );
});

Deno.test("returns the iCCP colour profile", async () => {
  const icc = Uint8Array.from({ length: 536 }, (_, i) => i % 256);
  const image = await decodePng(
    await makePng({ width: 2, height: 2, colorType: 2, depth: 8, sample: () => [1, 2, 3], icc }),
    limits,
  );
  assert.deepEqual(image.icc, icc);
});

Deno.test("refuses what isn't a sound PNG, or is too large", async () => {
  const good = await makePng({ width: 4, height: 4, colorType: 2, depth: 8, sample: () => [1, 2, 3] });
  const refuses = async (bytes: Uint8Array, why: string, custom = limits) =>
    await assert.rejects(() => decodePng(bytes, custom), PngError, why);

  await refuses(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9]), "not a PNG");
  await refuses(good.subarray(0, good.length - 30), "truncated");
  await refuses(good, "too many pixels", { maxSide: 4096, maxPixels: 15 });
  await refuses(good, "too wide", { maxSide: 3, maxPixels: 100 });

  // A header that promises 4×4 but data that inflates to far more (a "bomb").
  const bomb = await makePng({ width: 400, height: 400, colorType: 2, depth: 8, sample: () => [0, 0, 0] });
  const ihdr = 16; // width at signature (8) + length (4) + type (4)
  const small = bomb.slice();
  new DataView(small.buffer).setUint32(ihdr, 4);
  new DataView(small.buffer).setUint32(ihdr + 4, 4);
  await refuses(small, "more data than the header says");

  // Filter type 7 doesn't exist.
  const raw = new Uint8Array(1 + 4 * 3);
  raw[0] = 7;
  const broken = await makePng({ width: 4, height: 1, colorType: 2, depth: 8, sample: () => [0, 0, 0], filters: [0] });
  const body = await zlib(raw);
  const idat = new Uint8Array(12 + body.length);
  new DataView(idat.buffer).setUint32(0, body.length);
  idat.set([0x49, 0x44, 0x41, 0x54], 4);
  idat.set(body, 8);
  const header = broken.subarray(0, 8 + 25);
  const end = broken.subarray(broken.length - 12);
  const withBadFilter = new Uint8Array([...header, ...idat, ...end]);
  await refuses(withBadFilter, "unknown filter");

  // Palette images need a palette; colour type 2 can't be 4 bits.
  const noPalette = await makePng({ width: 2, height: 2, colorType: 3, depth: 8, sample: () => [0] });
  await refuses(noPalette, "no palette");
  const badDepth = good.slice();
  badDepth[8 + 8 + 8] = 4;
  await refuses(badDepth, "bad colour type or depth");
});

Deno.test("inflate stops at the size it was told", async () => {
  const data = await zlib(new Uint8Array(1000));
  assert.equal((await inflate(data, 1000)).length, 1000);
  await assert.rejects(() => inflate(data, 999), PngError);
  await assert.rejects(() => inflate(new Uint8Array([1, 2, 3]), 10), PngError);
});
