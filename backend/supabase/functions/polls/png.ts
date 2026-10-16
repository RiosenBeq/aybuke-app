// A PNG decoder for poll pictures: every colour type and bit depth of the PNG
// spec, Adam7 interlacing, palette and tRNS transparency, and the iCCP
// colour profile; out come 8-bit RGBA pixels. zlib data goes through the
// platform's DecompressionStream, stopped at the size the header promises,
// so a small file can't inflate into a large one. Chunks other than these
// (text, time, EXIF…) are skipped: nothing of them reaches the poll.

export interface DecodedImage {
  width: number;
  height: number;
  /** RGBA, 8 bits per channel, rows top to bottom. */
  data: Uint8Array;
  /** The ICC colour profile, when the file has one. */
  icc?: Uint8Array;
  /** Whether any pixel is less than fully opaque. */
  hasAlpha: boolean;
}

export class PngError extends Error {}

export interface PngLimits {
  maxSide: number;
  maxPixels: number;
}

const SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const CHANNELS: Record<number, number> = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };
const DEPTHS: Record<number, number[]> = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
/** Adam7: [x0, y0, dx, dy] per pass. */
const ADAM7 = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]];
const MAX_ICC = 65_536;

const u32 = (b: Uint8Array, i: number) => ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;
const fail = (message: string): never => {
  throw new PngError(message);
};

/** zlib data, inflated; refuses to produce more than `maxBytes`. */
export async function inflate(data: Uint8Array, maxBytes: number): Promise<Uint8Array> {
  const out = new Uint8Array(maxBytes);
  let offset = 0;
  const reader = new Blob([data.slice()]).stream().pipeThrough(new DecompressionStream("deflate")).getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (offset + value.length > maxBytes) {
        await reader.cancel().catch(() => {});
        fail("more data than the header says");
      }
      out.set(value, offset);
      offset += value.length;
    }
  } catch (error) {
    if (error instanceof PngError) throw error;
    fail("corrupt compressed data");
  }
  return out.subarray(0, offset);
}

function rowBytes(width: number, channels: number, depth: number): number {
  return Math.ceil((width * channels * depth) / 8);
}

/** Undoes the five PNG filters in place, one scanline at a time (each starts with its filter type). */
function unfilter(data: Uint8Array, offset: number, rows: number, stride: number, bpp: number): number {
  let previous = -1;
  for (let y = 0; y < rows; y++) {
    const filter = data[offset];
    const start = offset + 1;
    if (filter > 4) fail(`unknown filter ${filter}`);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? data[start + x - bpp] : 0;
      const b = previous >= 0 ? data[previous + x] : 0;
      const c = previous >= 0 && x >= bpp ? data[previous + x - bpp] : 0;
      let add = 0;
      switch (filter) {
        case 1:
          add = a;
          break;
        case 2:
          add = b;
          break;
        case 3:
          add = (a + b) >> 1;
          break;
        case 4: {
          const p = a + b - c;
          const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
          add = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          break;
        }
      }
      data[start + x] = (data[start + x] + add) & 0xff;
    }
    previous = start;
    offset = start + stride;
  }
  return offset;
}

interface Header {
  width: number;
  height: number;
  depth: number;
  colorType: number;
  interlace: number;
  palette?: Uint8Array;
  /** Palette alpha (type 3), or the transparent sample(s) for types 0 and 2, at the image's bit depth. */
  transparency?: Uint8Array;
}

/** One sample (at most 16 bits) of a scanline, scaled to 8 bits. */
function sampleReader(depth: number) {
  if (depth === 8) return (line: Uint8Array, index: number) => line[index];
  if (depth === 16) return (line: Uint8Array, index: number) => line[index * 2];
  const perByte = 8 / depth;
  const mask = (1 << depth) - 1;
  return (line: Uint8Array, index: number) =>
    (line[Math.floor(index / perByte)] >> (8 - depth * ((index % perByte) + 1))) & mask;
}

/** The raw sample at full depth (for tRNS comparisons and palette indices). */
function rawReader(depth: number) {
  if (depth === 16) return (line: Uint8Array, index: number) => (line[index * 2] << 8) | line[index * 2 + 1];
  if (depth === 8) return (line: Uint8Array, index: number) => line[index];
  const perByte = 8 / depth;
  const mask = (1 << depth) - 1;
  return (line: Uint8Array, index: number) =>
    (line[Math.floor(index / perByte)] >> (8 - depth * ((index % perByte) + 1))) & mask;
}

/** Writes one scanline's pixels into the RGBA image, at every dx-th pixel from x0 of row y. */
function writeLine(h: Header, line: Uint8Array, count: number, out: Uint8Array, y: number, x0: number, dx: number) {
  const channels = CHANNELS[h.colorType];
  const read = sampleReader(h.depth);
  const raw = rawReader(h.depth);
  const grayScale = h.depth < 8 ? 255 / ((1 << h.depth) - 1) : 1;
  const tr = h.transparency;
  const u16 = (b: Uint8Array, i: number) => (b[i] << 8) | b[i + 1];
  for (let i = 0; i < count; i++) {
    const o = (y * h.width + x0 + i * dx) * 4;
    let r: number, g: number, b: number, a = 255;
    switch (h.colorType) {
      case 0: {
        const v = read(line, i);
        r = g = b = h.depth < 8 ? Math.round(v * grayScale) : v;
        if (tr && tr.length >= 2 && raw(line, i) === u16(tr, 0)) a = 0;
        break;
      }
      case 2: {
        r = read(line, i * 3);
        g = read(line, i * 3 + 1);
        b = read(line, i * 3 + 2);
        if (
          tr && tr.length >= 6 && raw(line, i * 3) === u16(tr, 0) && raw(line, i * 3 + 1) === u16(tr, 2) &&
          raw(line, i * 3 + 2) === u16(tr, 4)
        ) a = 0;
        break;
      }
      case 3: {
        const index = raw(line, i);
        const palette = h.palette!;
        if (index * 3 + 2 >= palette.length) fail("palette index out of range");
        r = palette[index * 3];
        g = palette[index * 3 + 1];
        b = palette[index * 3 + 2];
        if (tr && index < tr.length) a = tr[index];
        break;
      }
      case 4:
        r = g = b = read(line, i * channels);
        a = read(line, i * channels + 1);
        break;
      default: // 6
        r = read(line, i * 4);
        g = read(line, i * 4 + 1);
        b = read(line, i * 4 + 2);
        a = read(line, i * 4 + 3);
    }
    out[o] = r;
    out[o + 1] = g;
    out[o + 2] = b;
    out[o + 3] = a;
  }
}

/** Decodes a PNG into RGBA, or throws PngError. */
export async function decodePng(bytes: Uint8Array, limits: PngLimits): Promise<DecodedImage> {
  if (bytes.length < 8 || !SIGNATURE.every((value, i) => bytes[i] === value)) fail("not a PNG");
  let header: Header | undefined;
  const idat: Uint8Array[] = [];
  let idatSize = 0;
  let iccCompressed: Uint8Array | undefined;
  let offset = 8;
  let ended = false;
  while (offset + 12 <= bytes.length) {
    const length = u32(bytes, offset);
    const type = String.fromCharCode(...bytes.subarray(offset + 4, offset + 8));
    const start = offset + 8;
    const end = start + length;
    if (end + 4 > bytes.length) fail("truncated chunk");
    const chunk = bytes.subarray(start, end);
    if (!header && type !== "IHDR") fail("IHDR must come first");
    switch (type) {
      case "IHDR": {
        if (header || length !== 13) fail("bad IHDR");
        const width = u32(chunk, 0);
        const height = u32(chunk, 4);
        const depth = chunk[8];
        const colorType = chunk[9];
        if (chunk[10] !== 0 || chunk[11] !== 0 || chunk[12] > 1) fail("unsupported compression, filter or interlace");
        if (!(colorType in CHANNELS) || !DEPTHS[colorType].includes(depth)) fail("bad colour type or depth");
        if (width < 1 || height < 1 || width > limits.maxSide || height > limits.maxSide) fail("too large");
        if (width * height > limits.maxPixels) fail("too large");
        header = { width, height, depth, colorType, interlace: chunk[12] };
        break;
      }
      case "PLTE":
        if (length % 3 !== 0 || length === 0 || length > 768) fail("bad palette");
        header!.palette = chunk.slice();
        break;
      case "tRNS":
        header!.transparency = chunk.slice();
        break;
      case "iCCP": {
        // Name (1–79 bytes), a 0 byte, compression method 0, then the zlib profile.
        const zero = chunk.indexOf(0);
        if (zero >= 1 && zero <= 79 && chunk[zero + 1] === 0) iccCompressed = chunk.slice(zero + 2);
        break;
      }
      case "IDAT":
        idat.push(chunk);
        idatSize += length;
        break;
      case "IEND":
        ended = true;
        break;
    }
    if (ended) break;
    offset = end + 4; // skip the CRC
  }
  if (!header) fail("no IHDR");
  const h = header!;
  if (h.colorType === 3 && !h.palette) fail("no palette");
  if (idatSize === 0) fail("no image data");

  const channels = CHANNELS[h.colorType];
  const bpp = Math.max(1, (channels * h.depth) >> 3);
  const passes = h.interlace === 1
    ? ADAM7.map(([x0, y0, dx, dy]) => ({
      x0,
      y0,
      dx,
      dy,
      width: Math.ceil(Math.max(0, h.width - x0) / dx),
      height: Math.ceil(Math.max(0, h.height - y0) / dy),
    }))
    : [{ x0: 0, y0: 0, dx: 1, dy: 1, width: h.width, height: h.height }];
  let expected = 0;
  for (const pass of passes) {
    if (pass.width > 0 && pass.height > 0) expected += pass.height * (1 + rowBytes(pass.width, channels, h.depth));
  }

  const compressed = new Uint8Array(idatSize);
  let at = 0;
  for (const part of idat) {
    compressed.set(part, at);
    at += part.length;
  }
  const data = await inflate(compressed, expected);
  if (data.length < expected) fail("not enough image data");

  const out = new Uint8Array(h.width * h.height * 4);
  let position = 0;
  for (const pass of passes) {
    if (pass.width === 0 || pass.height === 0) continue;
    const stride = rowBytes(pass.width, channels, h.depth);
    const next = unfilter(data, position, pass.height, stride, bpp);
    for (let row = 0; row < pass.height; row++) {
      const start = position + row * (stride + 1) + 1;
      writeLine(h, data.subarray(start, start + stride), pass.width, out, pass.y0 + row * pass.dy, pass.x0, pass.dx);
    }
    position = next;
  }

  let hasAlpha = false;
  for (let i = 3; i < out.length; i += 4) {
    if (out[i] !== 255) {
      hasAlpha = true;
      break;
    }
  }
  let icc: Uint8Array | undefined;
  if (iccCompressed) icc = await inflate(iccCompressed, MAX_ICC).catch(() => undefined);
  return { width: h.width, height: h.height, data: out, icc: icc && icc.length > 0 ? icc : undefined, hasAlpha };
}
