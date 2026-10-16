// For tests only: pictures made in code, so the poll tests need no image
// files. JPEGs come from jpeg.ts (decoded by jpeg-js, an independent
// decoder), PNGs from a small encoder written against the PNG spec, with
// every filter type, bit depth and Adam7 interlacing.
import { encodeJpeg } from "./jpeg.ts";
import { base64 } from "./picture.ts";

/** RGBA pixels from a function of x and y. */
export function pixels(width: number, height: number, color: (x: number, y: number) => number[]): Uint8Array {
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const [r, g, b, a = 255] = color(x, y);
      data.set([r, g, b, a], (y * width + x) * 4);
    }
  }
  return data;
}

/** A smooth test picture: red rises to the right, green downwards, blue is constant. */
export const gradient = (width: number, height: number) =>
  pixels(
    width,
    height,
    (x, y) => [Math.round((x / Math.max(1, width - 1)) * 255), Math.round((y / Math.max(1, height - 1)) * 255), 96],
  );

export function makeJpeg(width: number, height: number, data = gradient(width, height), quality = 90): Uint8Array {
  return encodeJpeg(data, width, height, { quality });
}

/** The JPEG with an EXIF APP1 segment (orientation, and a fake GPS tag) right after SOI. */
export function withExif(jpeg: Uint8Array, orientation: number, little = false): Uint8Array {
  const tiff: number[] = [];
  const u16 = (v: number) => little ? [v & 0xff, v >> 8] : [v >> 8, v & 0xff];
  const u32 = (v: number) =>
    little
      ? [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, v >>> 24]
      : [v >>> 24, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
  tiff.push(...(little ? [0x49, 0x49] : [0x4d, 0x4d]), ...u16(42), ...u32(8));
  // Two entries: ImageDescription (ASCII, 4 bytes inline: "GPS") and Orientation.
  tiff.push(...u16(2));
  tiff.push(...u16(0x010e), ...u16(2), ...u32(4), 0x47, 0x50, 0x53, 0x00);
  tiff.push(...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0);
  tiff.push(...u32(0));
  const payload = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff];
  const segment = [0xff, 0xe1, (payload.length + 2) >> 8, (payload.length + 2) & 0xff, ...payload];
  const out = new Uint8Array(jpeg.length + segment.length);
  out.set(jpeg.subarray(0, 2));
  out.set(segment, 2);
  out.set(jpeg.subarray(2), 2 + segment.length);
  return out;
}

/** The JPEG with other dimensions written into its frame header (the pixel data stays as it was). */
export function withFrameSize(jpeg: Uint8Array, width: number, height: number): Uint8Array {
  const out = jpeg.slice();
  let i = 2;
  while (i + 4 <= out.length && out[i] === 0xff) {
    if (out[i + 1] === 0xc0) {
      out.set([height >> 8, height & 0xff, width >> 8, width & 0xff], i + 5);
      return out;
    }
    i += 2 + ((out[i + 2] << 8) | out[i + 3]);
  }
  throw new Error("no frame header");
}

export function jpegUri(bytes: Uint8Array): string {
  return `data:image/jpeg;base64,${base64(bytes)}`;
}

export function pngUri(bytes: Uint8Array): string {
  return `data:image/png;base64,${base64(bytes)}`;
}

// MARK: - PNG

export async function zlib(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data.slice()]).stream().pipeThrough(new CompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(12 + data.length);
  const view = new DataView(out.buffer);
  view.setUint32(0, data.length);
  for (let i = 0; i < 4; i++) out[4 + i] = type.charCodeAt(i);
  out.set(data, 8);
  view.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)));
  return out;
}

export interface PngSpec {
  width: number;
  height: number;
  colorType: 0 | 2 | 3 | 4 | 6;
  depth: 1 | 2 | 4 | 8 | 16;
  /** Samples per pixel, in channel order, at the image's depth (palette indices for type 3). */
  sample(x: number, y: number): number[];
  palette?: number[][];
  transparency?: number[];
  /** The filter for each scanline (cycled); default all five in turn. */
  filters?: number[];
  interlace?: boolean;
  icc?: Uint8Array;
}

const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 } as const;
const ADAM7 = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]];

function packRow(spec: PngSpec, xs: number[], y: number): Uint8Array {
  const channels = CHANNELS[spec.colorType];
  const bits = xs.length * channels * spec.depth;
  const row = new Uint8Array(Math.ceil(bits / 8));
  let bit = 0;
  for (const x of xs) {
    for (const value of spec.sample(x, y)) {
      if (spec.depth === 16) {
        row[bit / 8] = value >> 8;
        row[bit / 8 + 1] = value & 0xff;
      } else if (spec.depth === 8) {
        row[bit / 8] = value;
      } else {
        row[bit >> 3] |= value << (8 - spec.depth - (bit & 7));
      }
      bit += spec.depth;
    }
  }
  return row;
}

function filterRow(row: Uint8Array, previous: Uint8Array | undefined, bpp: number, type: number): Uint8Array {
  const out = new Uint8Array(row.length + 1);
  out[0] = type;
  for (let x = 0; x < row.length; x++) {
    const a = x >= bpp ? row[x - bpp] : 0;
    const b = previous ? previous[x] : 0;
    const c = previous && x >= bpp ? previous[x - bpp] : 0;
    let predictor = 0;
    if (type === 1) predictor = a;
    else if (type === 2) predictor = b;
    else if (type === 3) predictor = (a + b) >> 1;
    else if (type === 4) {
      const p = a + b - c;
      const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      predictor = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
    }
    out[x + 1] = (row[x] - predictor) & 0xff;
  }
  return out;
}

export async function makePng(spec: PngSpec): Promise<Uint8Array> {
  const channels = CHANNELS[spec.colorType];
  const bpp = Math.max(1, (channels * spec.depth) >> 3);
  const filters = spec.filters ?? [0, 1, 2, 3, 4];
  const passes = spec.interlace ? ADAM7 : [[0, 0, 1, 1]];
  const parts: Uint8Array[] = [];
  let line = 0;
  for (const [x0, y0, dx, dy] of passes) {
    const xs: number[] = [];
    for (let x = x0; x < spec.width; x += dx) xs.push(x);
    if (xs.length === 0) continue;
    let previous: Uint8Array | undefined;
    for (let y = y0; y < spec.height; y += dy) {
      const row = packRow(spec, xs, y);
      parts.push(filterRow(row, previous, bpp, filters[line++ % filters.length]));
      previous = row;
    }
  }
  const raw = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    raw.set(part, offset);
    offset += part.length;
  }
  const header = new Uint8Array(13);
  const view = new DataView(header.buffer);
  view.setUint32(0, spec.width);
  view.setUint32(4, spec.height);
  header.set([spec.depth, spec.colorType, 0, 0, spec.interlace ? 1 : 0], 8);
  const chunks = [chunk("IHDR", header)];
  if (spec.icc) {
    const name = new TextEncoder().encode("Display P3");
    const profile = await zlib(spec.icc);
    const body = new Uint8Array(name.length + 2 + profile.length);
    body.set(name);
    body.set(profile, name.length + 2);
    chunks.push(chunk("iCCP", body));
  }
  chunks.push(chunk("tEXt", new TextEncoder().encode("Comment\0private text")));
  if (spec.palette) chunks.push(chunk("PLTE", Uint8Array.from(spec.palette.flat())));
  if (spec.transparency) chunks.push(chunk("tRNS", Uint8Array.from(spec.transparency)));
  const compressed = await zlib(raw);
  // Split over two IDAT chunks, as encoders may.
  const half = Math.floor(compressed.length / 2);
  chunks.push(chunk("IDAT", compressed.subarray(0, half)), chunk("IDAT", compressed.subarray(half)));
  chunks.push(chunk("IEND", new Uint8Array()));
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const out = new Uint8Array(8 + chunks.reduce((n, c) => n + c.length, 0));
  out.set(signature);
  offset = 8;
  for (const c of chunks) {
    out.set(c, offset);
    offset += c.length;
  }
  return out;
}
