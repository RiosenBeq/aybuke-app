// A small baseline JPEG encoder (YCbCr 4:2:0, the standard tables of the
// JPEG spec, Annex K) and the two things polls read from a JPEG's header: the
// EXIF orientation and the ICC colour profile. Poll pictures are re-encoded
// with it: 4:2:0 makes them 10–20% smaller than jpeg-js's 4:4:4 at the same
// quality (measured on the marketing samples), egress the free plan keeps.
//
// Nothing else from the source survives: no EXIF (location, camera, dates),
// no XMP, no comments. Only the colour profile is copied, so a Display P3
// photo keeps its colours.

// MARK: - Tables

/** jpeg_natural_order: the natural (row-major) index of each zigzag position. */
// deno-fmt-ignore
const ZIGZAG = new Uint8Array([
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
  12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
  58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
]);

/** Annex K.1, natural order. */
// deno-fmt-ignore
const LUMINANCE_QUANT = [
  16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55,
  14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
  49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
];
// deno-fmt-ignore
const CHROMINANCE_QUANT = [
  17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99,
  24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
];

/** A Huffman table as the DHT segment carries it: the code count per length 1–16, then the symbols. */
export interface HuffmanSpec {
  counts: number[];
  symbols: number[];
}

/** Annex K.3. */
export const DC_LUMINANCE: HuffmanSpec = {
  counts: [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
  symbols: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
};
export const DC_CHROMINANCE: HuffmanSpec = {
  counts: [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
  symbols: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
};
// deno-fmt-ignore
export const AC_LUMINANCE: HuffmanSpec = {
  counts: [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d],
  symbols: [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
  ],
};
// deno-fmt-ignore
export const AC_CHROMINANCE: HuffmanSpec = {
  counts: [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77],
  symbols: [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
    0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
    0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
    0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
    0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
  ],
};

/** The AAN scale factors the float DCT leaves in its output (IJG jfdctflt.c). */
const AAN_SCALE = [1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.5411961, 0.275899379];

/** IJG's quality scaling of a base table (1–100; 50 is the table as printed). */
export function scaledTable(base: number[], quality: number): Uint8Array {
  const q = Math.min(100, Math.max(1, Math.round(quality)));
  const scale = q < 50 ? Math.floor(5000 / q) : 200 - q * 2;
  return Uint8Array.from(base, (value) => Math.min(255, Math.max(1, Math.floor((value * scale + 50) / 100))));
}

/** 1 / (quant × the DCT's own scale), natural order: multiplying by it quantizes a coefficient. */
function divisors(table: Uint8Array): Float32Array {
  const out = new Float32Array(64);
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      out[row * 8 + col] = 1 / (table[row * 8 + col] * AAN_SCALE[row] * AAN_SCALE[col] * 8);
    }
  }
  return out;
}

/** Canonical codes for a table: code and length per symbol. */
function huffmanCodes(spec: HuffmanSpec): { code: Uint16Array; length: Uint8Array } {
  const code = new Uint16Array(256);
  const length = new Uint8Array(256);
  let next = 0;
  let k = 0;
  for (let bits = 1; bits <= 16; bits++) {
    for (let i = 0; i < spec.counts[bits - 1]; i++) {
      const symbol = spec.symbols[k++];
      code[symbol] = next++;
      length[symbol] = bits;
    }
    next <<= 1;
  }
  return { code, length };
}

const DC_Y = huffmanCodes(DC_LUMINANCE);
const AC_Y = huffmanCodes(AC_LUMINANCE);
const DC_C = huffmanCodes(DC_CHROMINANCE);
const AC_C = huffmanCodes(AC_CHROMINANCE);

// MARK: - Bits

class ByteWriter {
  private buffer = new Uint8Array(64 * 1024);
  length = 0;
  private bits = 0;
  private bitCount = 0;

  private ensure(extra: number) {
    if (this.length + extra <= this.buffer.length) return;
    const grown = new Uint8Array(Math.max(this.buffer.length * 2, this.length + extra));
    grown.set(this.buffer.subarray(0, this.length));
    this.buffer = grown;
  }

  byte(value: number) {
    this.ensure(1);
    this.buffer[this.length++] = value & 0xff;
  }

  word(value: number) {
    this.byte(value >> 8);
    this.byte(value);
  }

  bytes(values: ArrayLike<number>) {
    this.ensure(values.length);
    for (let i = 0; i < values.length; i++) this.buffer[this.length++] = values[i] & 0xff;
  }

  /** Entropy-coded bits, most significant first, with a 0x00 after every 0xFF. */
  put(code: number, count: number) {
    if (count === 0) return;
    this.bits = (this.bits << count) | (code & ((1 << count) - 1));
    this.bitCount += count;
    while (this.bitCount >= 8) {
      const value = (this.bits >> (this.bitCount - 8)) & 0xff;
      this.byte(value);
      if (value === 0xff) this.byte(0);
      this.bitCount -= 8;
    }
    this.bits &= (1 << this.bitCount) - 1;
  }

  /** Pads the last byte with 1 bits, as the spec asks. */
  flushBits() {
    if (this.bitCount > 0) this.put(0x7f, 8 - this.bitCount);
  }

  result(): Uint8Array {
    return this.buffer.slice(0, this.length);
  }
}

// MARK: - DCT and entropy coding

/** In-place forward DCT of an 8×8 block (AAN, IJG jfdctflt.c); the output carries AAN_SCALE × 8. */
function forwardDCT(d: Float32Array) {
  for (let pass = 0; pass < 2; pass++) {
    const step = pass === 0 ? 1 : 8;
    const stride = pass === 0 ? 8 : 1;
    for (let line = 0; line < 8; line++) {
      const o = line * stride;
      const i0 = o, i1 = o + step, i2 = o + 2 * step, i3 = o + 3 * step;
      const i4 = o + 4 * step, i5 = o + 5 * step, i6 = o + 6 * step, i7 = o + 7 * step;
      const tmp0 = d[i0] + d[i7];
      const tmp7 = d[i0] - d[i7];
      const tmp1 = d[i1] + d[i6];
      const tmp6 = d[i1] - d[i6];
      const tmp2 = d[i2] + d[i5];
      const tmp5 = d[i2] - d[i5];
      const tmp3 = d[i3] + d[i4];
      const tmp4 = d[i3] - d[i4];

      let tmp10 = tmp0 + tmp3;
      const tmp13 = tmp0 - tmp3;
      let tmp11 = tmp1 + tmp2;
      let tmp12 = tmp1 - tmp2;
      d[i0] = tmp10 + tmp11;
      d[i4] = tmp10 - tmp11;
      const z1 = (tmp12 + tmp13) * 0.707106781;
      d[i2] = tmp13 + z1;
      d[i6] = tmp13 - z1;

      tmp10 = tmp4 + tmp5;
      tmp11 = tmp5 + tmp6;
      tmp12 = tmp6 + tmp7;
      const z5 = (tmp10 - tmp12) * 0.382683433;
      const z2 = 0.5411961 * tmp10 + z5;
      const z4 = 1.306562965 * tmp12 + z5;
      const z3 = tmp11 * 0.707106781;
      const z11 = tmp7 + z3;
      const z13 = tmp7 - z3;
      d[i5] = z13 + z2;
      d[i3] = z13 - z2;
      d[i1] = z11 + z4;
      d[i7] = z11 - z4;
    }
  }
}

/** The bits a value needs (its "category"), 0 for 0. */
function category(value: number): number {
  return value === 0 ? 0 : 32 - Math.clz32(Math.abs(value));
}

/** The value's bits as JPEG writes them: negative values as their one's complement. */
function magnitudeBits(value: number, size: number): number {
  return value < 0 ? (value - 1) & ((1 << size) - 1) : value;
}

const block = new Float32Array(64);
const quantized = new Int32Array(64);

/** DCT, quantization and Huffman coding of one block; returns its DC value for the next one's difference. */
function encodeBlock(
  out: ByteWriter,
  divisor: Float32Array,
  dc: { code: Uint16Array; length: Uint8Array },
  ac: { code: Uint16Array; length: Uint8Array },
  previousDC: number,
): number {
  forwardDCT(block);
  for (let k = 0; k < 64; k++) {
    const i = ZIGZAG[k];
    const value = block[i] * divisor[i];
    const rounded = value > 0 ? Math.floor(value + 0.5) : Math.ceil(value - 0.5);
    // The Huffman tables hold AC magnitudes up to 10 bits (DC differences up to 11).
    quantized[k] = k === 0 ? rounded : Math.max(-1023, Math.min(1023, rounded));
  }
  const diff = quantized[0] - previousDC;
  const dcSize = category(diff);
  out.put(dc.code[dcSize], dc.length[dcSize]);
  out.put(magnitudeBits(diff, dcSize), dcSize);

  let run = 0;
  for (let k = 1; k < 64; k++) {
    const value = quantized[k];
    if (value === 0) {
      run++;
      continue;
    }
    while (run > 15) {
      out.put(ac.code[0xf0], ac.length[0xf0]);
      run -= 16;
    }
    const size = category(value);
    const symbol = (run << 4) | size;
    out.put(ac.code[symbol], ac.length[symbol]);
    out.put(magnitudeBits(value, size), size);
    run = 0;
  }
  if (run > 0) out.put(ac.code[0x00], ac.length[0x00]);
  return quantized[0];
}

// MARK: - Headers

function writeHuffmanTable(out: ByteWriter, tableClass: number, id: number, spec: HuffmanSpec) {
  out.byte((tableClass << 4) | id);
  out.bytes(spec.counts);
  out.bytes(spec.symbols);
}

/** APP2 ICC_PROFILE segments (a profile larger than one segment is split, as the ICC spec says). */
function writeICC(out: ByteWriter, icc: Uint8Array) {
  const chunk = 65519; // 65535 − 2 (length) − 14 ("ICC_PROFILE\0", sequence, count)
  const count = Math.ceil(icc.length / chunk);
  if (count === 0 || count > 255) return;
  for (let i = 0; i < count; i++) {
    const part = icc.subarray(i * chunk, Math.min(icc.length, (i + 1) * chunk));
    out.word(0xffe2);
    out.word(2 + 14 + part.length);
    out.bytes([0x49, 0x43, 0x43, 0x5f, 0x50, 0x52, 0x4f, 0x46, 0x49, 0x4c, 0x45, 0x00]); // ICC_PROFILE\0
    out.byte(i + 1);
    out.byte(count);
    out.bytes(part);
  }
}

export interface EncodeOptions {
  /** IJG's scale, 10–95 here (default 80). */
  quality?: number;
  /** An ICC colour profile to embed (Display P3, say). */
  icc?: Uint8Array;
}

/**
 * Baseline JPEG, YCbCr 4:2:0, from RGBA pixels (alpha ignored: flatten first).
 * JFIF, an optional ICC profile, and nothing else.
 */
export function encodeJpeg(rgba: Uint8Array, width: number, height: number, options: EncodeOptions = {}): Uint8Array {
  if (width < 1 || height < 1 || width > 65535 || height > 65535) throw new RangeError("bad size");
  if (rgba.length < width * height * 4) throw new RangeError("not enough pixels");
  const quality = Math.min(95, Math.max(10, options.quality ?? 80));
  const yTable = scaledTable(LUMINANCE_QUANT, quality);
  const cTable = scaledTable(CHROMINANCE_QUANT, quality);
  const yDivisor = divisors(yTable);
  const cDivisor = divisors(cTable);

  const out = new ByteWriter();
  out.word(0xffd8); // SOI
  out.word(0xffe0); // APP0 JFIF 1.01, no density, no thumbnail
  out.word(16);
  out.bytes([0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  if (options.icc && options.icc.length > 0) writeICC(out, options.icc);

  out.word(0xffdb); // DQT: both tables, zigzag order
  out.word(2 + 2 * 65);
  out.byte(0);
  for (let k = 0; k < 64; k++) out.byte(yTable[ZIGZAG[k]]);
  out.byte(1);
  for (let k = 0; k < 64; k++) out.byte(cTable[ZIGZAG[k]]);

  out.word(0xffc0); // SOF0: 8 bits, three components, Y at 2×2, Cb and Cr at 1×1
  out.word(17);
  out.byte(8);
  out.word(height);
  out.word(width);
  out.byte(3);
  out.bytes([1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]);

  out.word(0xffc4); // DHT
  out.word(
    2 + 4 * 17 + DC_LUMINANCE.symbols.length + AC_LUMINANCE.symbols.length + DC_CHROMINANCE.symbols.length +
      AC_CHROMINANCE.symbols.length,
  );
  writeHuffmanTable(out, 0, 0, DC_LUMINANCE);
  writeHuffmanTable(out, 1, 0, AC_LUMINANCE);
  writeHuffmanTable(out, 0, 1, DC_CHROMINANCE);
  writeHuffmanTable(out, 1, 1, AC_CHROMINANCE);

  out.word(0xffda); // SOS
  out.word(12);
  out.byte(3);
  out.bytes([1, 0x00, 2, 0x11, 3, 0x11]);
  out.bytes([0, 63, 0]);

  // Colour conversion once, edges repeated out to whole 16×16 MCUs.
  const mcuColumns = Math.ceil(width / 16);
  const mcuRows = Math.ceil(height / 16);
  const paddedWidth = mcuColumns * 16;
  const paddedHeight = mcuRows * 16;
  const lum = new Float32Array(paddedWidth * paddedHeight);
  const cb = new Float32Array(paddedWidth * paddedHeight);
  const cr = new Float32Array(paddedWidth * paddedHeight);
  for (let y = 0; y < paddedHeight; y++) {
    const sy = Math.min(y, height - 1);
    for (let x = 0; x < paddedWidth; x++) {
      const sx = Math.min(x, width - 1);
      const i = (sy * width + sx) * 4;
      const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      const o = y * paddedWidth + x;
      lum[o] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
      cb[o] = -0.168736 * r - 0.331264 * g + 0.5 * b;
      cr[o] = 0.5 * r - 0.418688 * g - 0.081312 * b;
    }
  }

  let dcY = 0, dcCb = 0, dcCr = 0;
  for (let my = 0; my < mcuRows; my++) {
    for (let mx = 0; mx < mcuColumns; mx++) {
      const left = mx * 16;
      const top = my * 16;
      for (let b = 0; b < 4; b++) {
        const bx = left + (b & 1) * 8;
        const by = top + (b >> 1) * 8;
        for (let y = 0; y < 8; y++) {
          const row = (by + y) * paddedWidth + bx;
          for (let x = 0; x < 8; x++) block[y * 8 + x] = lum[row + x];
        }
        dcY = encodeBlock(out, yDivisor, DC_Y, AC_Y, dcY);
      }
      // Each chroma sample is the mean of its 2×2 pixels.
      for (const [plane, which] of [[cb, 0], [cr, 1]] as const) {
        for (let y = 0; y < 8; y++) {
          const row0 = (top + y * 2) * paddedWidth + left;
          const row1 = row0 + paddedWidth;
          for (let x = 0; x < 8; x++) {
            const c = x * 2;
            block[y * 8 + x] = (plane[row0 + c] + plane[row0 + c + 1] + plane[row1 + c] + plane[row1 + c + 1]) / 4;
          }
        }
        if (which === 0) dcCb = encodeBlock(out, cDivisor, DC_C, AC_C, dcCb);
        else dcCr = encodeBlock(out, cDivisor, DC_C, AC_C, dcCr);
      }
    }
  }
  out.flushBits();
  out.word(0xffd9); // EOI
  return out.result();
}

// MARK: - Reading a JPEG's header

const u16 = (b: Uint8Array, i: number, little = false) => little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1];
const u32 = (b: Uint8Array, i: number, little = false) =>
  little
    ? (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0
    : ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;

/** The marker segments before the image data: [marker, payload start, payload end]. */
function* segments(b: Uint8Array): Generator<[number, number, number]> {
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return;
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return;
    while (i + 1 < b.length && b[i + 1] === 0xff) i++; // fill bytes
    const marker = b[i + 1];
    i += 2;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue; // no length
    if (marker === 0xd9 || marker === 0xda) return; // end, or the image data
    if (i + 2 > b.length) return;
    const length = u16(b, i);
    if (length < 2 || i + length > b.length) return;
    yield [marker, i + 2, i + length];
    i += length;
  }
}

/** The EXIF orientation (1–8), 1 when there is none or it can't be read. */
export function exifOrientation(b: Uint8Array): number {
  for (const [marker, start, end] of segments(b)) {
    if (marker !== 0xe1 || end - start < 14) continue;
    // "Exif\0\0", then a TIFF header.
    if (b[start] !== 0x45 || b[start + 1] !== 0x78 || b[start + 2] !== 0x69 || b[start + 3] !== 0x66) continue;
    const tiff = start + 6;
    const little = b[tiff] === 0x49 && b[tiff + 1] === 0x49;
    if (!little && !(b[tiff] === 0x4d && b[tiff + 1] === 0x4d)) return 1;
    if (u16(b, tiff + 2, little) !== 42) return 1;
    const ifd = tiff + u32(b, tiff + 4, little);
    if (ifd + 2 > end) return 1;
    const entries = u16(b, ifd, little);
    for (let e = 0; e < entries; e++) {
      const entry = ifd + 2 + e * 12;
      if (entry + 12 > end) return 1;
      if (u16(b, entry, little) !== 0x0112) continue;
      // SHORT, one value, stored in the entry itself.
      if (u16(b, entry + 2, little) !== 3) return 1;
      const value = u16(b, entry + 8, little);
      return value >= 1 && value <= 8 ? value : 1;
    }
    return 1;
  }
  return 1;
}

/** The ICC profile from APP2 ICC_PROFILE segments, in sequence order; undefined when absent or broken. */
export function iccProfile(b: Uint8Array, maxBytes = 65_536): Uint8Array | undefined {
  const parts = new Map<number, Uint8Array>();
  let count = 0;
  const signature = [0x49, 0x43, 0x43, 0x5f, 0x50, 0x52, 0x4f, 0x46, 0x49, 0x4c, 0x45, 0x00];
  for (const [marker, start, end] of segments(b)) {
    if (marker !== 0xe2 || end - start < 14) continue;
    if (!signature.every((value, k) => b[start + k] === value)) continue;
    const sequence = b[start + 12];
    const total = b[start + 13];
    if (sequence < 1 || total < 1 || sequence > total || (count && total !== count)) return undefined;
    count = total;
    parts.set(sequence, b.subarray(start + 14, end));
  }
  if (count === 0 || parts.size !== count) return undefined;
  let size = 0;
  for (const part of parts.values()) size += part.length;
  if (size === 0 || size > maxBytes) return undefined;
  const profile = new Uint8Array(size);
  let offset = 0;
  for (let sequence = 1; sequence <= count; sequence++) {
    const part = parts.get(sequence)!;
    profile.set(part, offset);
    offset += part.length;
  }
  return profile;
}
