// A poll picture, from the app's data URI to what friends see: a JPEG of at
// most 720 px on the long side, upright, on white where it was transparent,
// with nothing else (no EXIF, so no location, camera or dates) but a standard
// colour profile when it had one: Display P3 or sRGB IEC61966-2.1, recognised
// by the SHA-256 of their exact bytes (KNOWN_PROFILES). Any other profile is
// dropped: a crafted one could make browsers show colours, or a picture,
// Claude never saw. Claude checks this version, the only one that is stored.
//
//   screenPicture()   cheap, before admission: the data URI, the real type
//                     (JPEG or PNG), at most 1.5 MB, at most 4,096 px a side
//                     and 6 MP — read from the header, nothing decoded yet.
//   preparePicture()  after admission: decode (jpeg-js, or png.ts), orient,
//                     flatten, shrink (area average), encode (jpeg.ts, 4:2:0).
//
// About 0.1–0.3 s of CPU for a 1–6 MP photo, so two fit well inside an Edge
// Function's 2 s CPU budget.
import jpeg from "npm:jpeg-js@0.4.4";
import { checkImage, type ImageInfo } from "../_shared/input.ts";
import { encodeJpeg, exifOrientation, iccProfile } from "./jpeg.ts";
import { decodePng, PngError } from "./png.ts";

/** Decoded bytes; the contract says 1.5 MB. */
export const MAX_PICTURE_BYTES = 1_572_864;
export const MAX_PICTURE_SIDE = 4_096;
export const MAX_PICTURE_PIXELS = 6_000_000;
/** The long side of what is stored and shown. */
export const OUTPUT_SIDE = 720;
export const OUTPUT_QUALITY = 78;
const MAX_ICC_BYTES = 65_536;

/**
 * The colour profiles a picture may keep, by the SHA-256 (hex) of their bytes,
 * exactly as Apple ships them (polls/test_profiles.ts has the bytes).
 */
export const KNOWN_PROFILES: ReadonlyMap<string, string> = new Map([
  ["0ff6958f98684c61f6bbdce1368ddeaf3873baf84545baba482e920d92a914c0", "Display P3"],
  ["2b3aa1645779a9e634744faf9b01e9102b0c9b88fd6deced7934df86b949af7e", "sRGB IEC61966-2.1"],
]);

/** The profile when it's one of KNOWN_PROFILES, byte for byte; else undefined (the picture is read as sRGB). */
export async function knownProfile(icc: Uint8Array | undefined): Promise<Uint8Array | undefined> {
  if (!icc || icc.length === 0 || icc.length > MAX_ICC_BYTES) return undefined;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(icc)));
  const hex = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return KNOWN_PROFILES.has(hex) ? icc : undefined;
}

export interface Picture {
  jpeg: Uint8Array;
  width: number;
  height: number;
}

export type PictureProblem = { ok: false; code: "image_invalid" | "too_large"; reason: string };

/** A picture that passed screenPicture(): its bytes and what its header says. */
export interface Screened {
  ok: true;
  bytes: Uint8Array;
  info: ImageInfo;
}

const problem = (code: PictureProblem["code"], reason: string): PictureProblem => ({ ok: false, code, reason });

function decodeBase64(text: string): Uint8Array {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** The data URI as the contract allows it, without decoding a pixel. */
export function screenPicture(value: unknown): Screened | PictureProblem {
  const checked = checkImage(value);
  if (!checked.ok) return problem(checked.code, checked.reason);
  const { info } = checked;
  if (info.type !== "jpeg" && info.type !== "png") return problem("image_invalid", `${info.type} isn't accepted`);
  if (info.bytes > MAX_PICTURE_BYTES) return problem("too_large", `${info.bytes} bytes`);
  if (
    info.width > MAX_PICTURE_SIDE || info.height > MAX_PICTURE_SIDE || info.width * info.height > MAX_PICTURE_PIXELS
  ) {
    return problem("too_large", `${info.width}×${info.height}`);
  }
  const text = value as string;
  const bytes = decodeBase64(text.slice(text.indexOf(",") + 1));
  return { ok: true, bytes, info };
}

// MARK: - Pixels

interface Pixels {
  data: Uint8Array;
  width: number;
  height: number;
}

/** Transparent pixels on white (the page shows pictures on light cards). */
export function flattenOnWhite(data: Uint8Array) {
  for (let i = 0; i < data.length; i += 4) {
    const a = data[i + 3];
    if (a === 255) continue;
    const keep = a / 255;
    const white = 255 * (1 - keep);
    data[i] = Math.round(data[i] * keep + white);
    data[i + 1] = Math.round(data[i + 1] * keep + white);
    data[i + 2] = Math.round(data[i + 2] * keep + white);
    data[i + 3] = 255;
  }
}

/** For each output index, the source indices it covers and their weights (area averaging). */
function spans(source: number, target: number): { first: Int32Array; count: Int32Array; weights: Float32Array } {
  const scale = source / target;
  const first = new Int32Array(target);
  const count = new Int32Array(target);
  const maxCount = Math.ceil(scale) + 1;
  const weights = new Float32Array(target * maxCount);
  for (let t = 0; t < target; t++) {
    const start = t * scale;
    const end = Math.min(source, start + scale);
    const s0 = Math.floor(start);
    const s1 = Math.min(source, Math.ceil(end));
    first[t] = s0;
    count[t] = s1 - s0;
    for (let s = s0; s < s1; s++) {
      weights[t * maxCount + (s - s0)] = (Math.min(s + 1, end) - Math.max(s, start)) / scale;
    }
  }
  return { first, count, weights };
}

/** Shrinks RGB(A) pixels by area averaging (never enlarges); alpha comes out opaque. */
export function shrink(src: Pixels, width: number, height: number): Pixels {
  if (width >= src.width && height >= src.height) return src;
  const xs = spans(src.width, width);
  const ys = spans(src.height, height);
  const xStride = Math.ceil(src.width / width) + 1;
  const yStride = Math.ceil(src.height / height) + 1;
  // Rows first: src.width × src.height → width × src.height, as floats.
  const rows = new Float32Array(width * src.height * 3);
  for (let y = 0; y < src.height; y++) {
    for (let x = 0; x < width; x++) {
      let r = 0, g = 0, b = 0;
      const from = xs.first[x];
      for (let k = 0; k < xs.count[x]; k++) {
        const w = xs.weights[x * xStride + k];
        const i = (y * src.width + from + k) * 4;
        r += src.data[i] * w;
        g += src.data[i + 1] * w;
        b += src.data[i + 2] * w;
      }
      const o = (y * width + x) * 3;
      rows[o] = r;
      rows[o + 1] = g;
      rows[o + 2] = b;
    }
  }
  const out = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    const from = ys.first[y];
    for (let x = 0; x < width; x++) {
      let r = 0, g = 0, b = 0;
      for (let k = 0; k < ys.count[y]; k++) {
        const w = ys.weights[y * yStride + k];
        const i = ((from + k) * width + x) * 3;
        r += rows[i] * w;
        g += rows[i + 1] * w;
        b += rows[i + 2] * w;
      }
      const o = (y * width + x) * 4;
      out[o] = Math.min(255, Math.round(r));
      out[o + 1] = Math.min(255, Math.round(g));
      out[o + 2] = Math.min(255, Math.round(b));
      out[o + 3] = 255;
    }
  }
  return { data: out, width, height };
}

/** Turns stored pixels upright for an EXIF orientation (1–8). */
export function orient(src: Pixels, orientation: number): Pixels {
  if (orientation <= 1 || orientation > 8) return src;
  const { width: w, height: h } = src;
  const swap = orientation >= 5;
  const width = swap ? h : w;
  const height = swap ? w : h;
  const out = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sx: number, sy: number;
      switch (orientation) {
        case 2:
          sx = w - 1 - x, sy = y;
          break;
        case 3:
          sx = w - 1 - x, sy = h - 1 - y;
          break;
        case 4:
          sx = x, sy = h - 1 - y;
          break;
        case 5:
          sx = y, sy = x;
          break;
        case 6:
          sx = y, sy = h - 1 - x;
          break;
        case 7:
          sx = w - 1 - y, sy = h - 1 - x;
          break;
        default: // 8
          sx = w - 1 - y, sy = x;
      }
      const i = (sy * w + sx) * 4;
      const o = (y * width + x) * 4;
      out[o] = src.data[i];
      out[o + 1] = src.data[i + 1];
      out[o + 2] = src.data[i + 2];
      out[o + 3] = src.data[i + 3];
    }
  }
  return { data: out, width, height };
}

/** The size that fits OUTPUT_SIDE on the long side, never larger than the source. */
export function fittedSize(width: number, height: number, side = OUTPUT_SIDE): { width: number; height: number } {
  const scale = Math.min(1, side / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

// MARK: - The whole way

/** Decodes, orients, flattens, shrinks and re-encodes a screened picture. Never throws. */
export async function preparePicture(screened: Screened): Promise<{ ok: true; picture: Picture } | PictureProblem> {
  const { bytes, info } = screened;
  let pixels: Pixels;
  let icc: Uint8Array | undefined;
  let orientation = 1;
  try {
    if (info.type === "jpeg") {
      const decoded = jpeg.decode(bytes, {
        useTArray: true,
        formatAsRGBA: true,
        maxResolutionInMP: MAX_PICTURE_PIXELS / 1_000_000 + 0.1,
        maxMemoryUsageInMB: 160,
      });
      pixels = { data: decoded.data, width: decoded.width, height: decoded.height };
      orientation = exifOrientation(bytes);
      icc = iccProfile(bytes, MAX_ICC_BYTES);
    } else {
      const decoded = await decodePng(bytes, { maxSide: MAX_PICTURE_SIDE, maxPixels: MAX_PICTURE_PIXELS });
      if (decoded.hasAlpha) flattenOnWhite(decoded.data);
      pixels = decoded;
      icc = decoded.icc;
    }
  } catch (error) {
    const reason = error instanceof PngError || error instanceof Error ? error.message : "unreadable";
    return problem("image_invalid", reason.slice(0, 120));
  }
  if (pixels.width !== info.width || pixels.height !== info.height || pixels.width < 1 || pixels.height < 1) {
    return problem("image_invalid", "size doesn't match its header");
  }
  const target = fittedSize(pixels.width, pixels.height);
  const upright = orient(shrink(pixels, target.width, target.height), orientation);
  const profile = await knownProfile(icc);
  const encoded = encodeJpeg(upright.data, upright.width, upright.height, { quality: OUTPUT_QUALITY, icc: profile });
  return { ok: true, picture: { jpeg: encoded, width: upright.width, height: upright.height } };
}

/** The bytes as base64 (for the database and for Claude). */
export function base64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

export function dataUri(picture: Picture): string {
  return `data:image/jpeg;base64,${base64(picture.jpeg)}`;
}
