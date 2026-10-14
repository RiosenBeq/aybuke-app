// Input hardening for ai-image: what a request may carry before anything is
// charged or sent to a provider. Pure functions, unit-tested in input_test.ts.

/**
 * The app sends at most 800 characters of her words plus the edit guard and
 * "Only edit me" (PromptBuilder in AppCore), so a longer prompt didn't come
 * from the app.
 */
export const MAX_PROMPT_CHARS = 1_200;
/** Decoded bytes. The app sends JPEGs of at most 1,536 px on the long edge. */
export const MAX_IMAGE_BYTES = 6 * 1024 * 1024;
export const MAX_IMAGE_SIDE = 4_096;
export const MIN_IMAGE_SIDE = 16;
export const MAX_IMAGE_PIXELS = 4_096 * 4_096;

const VARIATION_SELECTOR = (cp: number) => (cp >= 0xfe00 && cp <= 0xfe0f) || (cp >= 0xe0100 && cp <= 0xe01ef);

/**
 * What the provider sees: NFKC, control characters as spaces, invisible format
 * characters (zero-width, bidi controls, soft hyphens, tag characters) and
 * variation selectors removed, whitespace collapsed. The policy checks both
 * this and the raw text (policy.ts folds the same characters).
 */
export function sanitizePrompt(raw: string): string {
  let out = "";
  for (const ch of raw.normalize("NFKC")) {
    const cp = ch.codePointAt(0)!;
    if (/^\p{Cc}$/u.test(ch) || cp === 0x2028 || cp === 0x2029) out += " ";
    else if (/^\p{Cf}$/u.test(ch) || VARIATION_SELECTOR(cp)) continue;
    else out += ch;
  }
  return out.replace(/\s+/gu, " ").trim();
}

export function promptLength(text: string): number {
  return [...text].length;
}

// MARK: Images

export type ImageType = "jpeg" | "png" | "webp" | "heic";

export interface ImageInfo {
  type: ImageType;
  width: number;
  height: number;
  bytes: number;
}

export type ImageCheck =
  | { ok: true; info: ImageInfo }
  | { ok: false; code: "image_invalid" | "too_large"; reason: string };

const DATA_URI = /^data:image\/(jpeg|jpg|png|webp|heic|heif);base64,/i;
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;
const DECLARED: Record<string, ImageType> = {
  jpeg: "jpeg",
  jpg: "jpeg",
  png: "png",
  webp: "webp",
  heic: "heic",
  heif: "heic",
};
const HEIF_BRANDS = new Set(["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1"]);
/** Enough for every header we read, and then some (EXIF and ICC segments come first in a JPEG). */
const HEAD_BASE64 = 512 * 1024;

const invalid = (reason: string): ImageCheck => ({ ok: false, code: "image_invalid", reason });

function decodeBase64(text: string): Uint8Array {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

const u16be = (b: Uint8Array, i: number) => (b[i] << 8) | b[i + 1];
const u32be = (b: Uint8Array, i: number) => ((b[i] << 24) >>> 0) + (b[i + 1] << 16) + (b[i + 2] << 8) + b[i + 3];
const u16le = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8);
const u24le = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);
const ascii = (b: Uint8Array, i: number, n: number) => String.fromCharCode(...b.subarray(i, i + n));

/** The file's real type from its first bytes (the data URI's label is only a claim). */
export function sniffType(b: Uint8Array): ImageType | undefined {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "jpeg";
  if (b.length >= 8 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((v, i) => b[i] === v)) return "png";
  if (b.length >= 12 && ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 4) === "WEBP") return "webp";
  if (b.length >= 12 && ascii(b, 4, 4) === "ftyp" && HEIF_BRANDS.has(ascii(b, 8, 4))) return "heic";
  return undefined;
}

function jpegSize(b: Uint8Array): [number, number] | undefined {
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return undefined;
    while (i + 1 < b.length && b[i + 1] === 0xff) i++; // fill bytes
    const marker = b[i + 1];
    i += 2;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue; // no length
    if (marker === 0xd9 || marker === 0xda) return undefined; // end, or scan data before any frame
    if (i + 2 > b.length) return undefined;
    const length = u16be(b, i);
    if (length < 2) return undefined;
    const isFrame = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrame) {
      if (i + 7 > b.length) return undefined;
      return [u16be(b, i + 5), u16be(b, i + 3)];
    }
    i += length;
  }
  return undefined;
}

function pngSize(b: Uint8Array): [number, number] | undefined {
  if (b.length < 24 || ascii(b, 12, 4) !== "IHDR") return undefined;
  return [u32be(b, 16), u32be(b, 20)];
}

function webpSize(b: Uint8Array): [number, number] | undefined {
  if (b.length < 30) return undefined;
  const chunk = ascii(b, 12, 4);
  if (chunk === "VP8X") return [1 + u24le(b, 24), 1 + u24le(b, 27)];
  if (chunk === "VP8 " && b[23] === 0x9d && b[24] === 0x01 && b[25] === 0x2a) {
    return [u16le(b, 26) & 0x3fff, u16le(b, 28) & 0x3fff];
  }
  if (chunk === "VP8L" && b[20] === 0x2f) {
    return [1 + (((b[22] & 0x3f) << 8) | b[21]), 1 + (((b[24] & 0x0f) << 10) | (b[23] << 2) | ((b[22] & 0xc0) >> 6))];
  }
  return undefined;
}

/** The largest image spatial extents ('ispe') box: the primary image, not a thumbnail. */
function heicSize(b: Uint8Array): [number, number] | undefined {
  let best: [number, number] | undefined;
  for (let i = 4; i + 16 <= b.length; i++) {
    if (b[i] !== 0x69 || ascii(b, i, 4) !== "ispe") continue; // "i"
    const width = u32be(b, i + 8);
    const height = u32be(b, i + 12);
    if (!best || width * height > best[0] * best[1]) best = [width, height];
  }
  return best;
}

function dimensions(type: ImageType, b: Uint8Array): [number, number] | undefined {
  switch (type) {
    case "jpeg":
      return jpegSize(b);
    case "png":
      return pngSize(b);
    case "webp":
      return webpSize(b);
    case "heic":
      return heicSize(b);
  }
}

/**
 * Checks a `data:image/…;base64,…` photo or mask: a supported type whose
 * bytes match its label (JPEG, PNG, WebP, HEIC), at most MAX_IMAGE_BYTES once
 * decoded, and readable dimensions within the limits. Fails closed: anything
 * it can't read is rejected.
 */
export function checkImage(value: unknown): ImageCheck {
  if (typeof value !== "string") return invalid("not a string");
  const match = DATA_URI.exec(value);
  if (!match) return invalid("not an image data URI");
  const payload = value.slice(match[0].length);
  if (payload.length === 0 || payload.length % 4 !== 0 || !BASE64.test(payload)) return invalid("bad base64");
  const padding = payload.endsWith("==") ? 2 : payload.endsWith("=") ? 1 : 0;
  const bytes = (payload.length / 4) * 3 - padding;
  if (bytes > MAX_IMAGE_BYTES) return { ok: false, code: "too_large", reason: `${bytes} bytes` };

  let head = decodeBase64(payload.slice(0, Math.min(payload.length, HEAD_BASE64)));
  const type = sniffType(head);
  if (!type) return invalid("unknown file type");
  if (type !== DECLARED[match[1].toLowerCase()]) return invalid(`labelled ${match[1]}, but it's ${type}`);
  let size = dimensions(type, head);
  if (!size && type === "jpeg" && payload.length > HEAD_BASE64) {
    head = decodeBase64(payload); // the frame header sits after unusually large metadata
    size = dimensions(type, head);
  }
  if (!size) return invalid("unreadable dimensions");
  const [width, height] = size;
  if (
    width < MIN_IMAGE_SIDE || height < MIN_IMAGE_SIDE || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE ||
    width * height > MAX_IMAGE_PIXELS
  ) {
    return invalid(`${width}×${height}`);
  }
  return { ok: true, info: { type, width, height, bytes } };
}

// MARK: Client address

function isIPv4(text: string): boolean {
  const parts = text.split(".");
  return parts.length === 4 && parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255);
}

/** Expands an IPv6 address to 8 groups, or undefined if it isn't one. */
function ipv6Groups(text: string): number[] | undefined {
  let address = text.toLowerCase();
  if (address.startsWith("[") && address.endsWith("]")) address = address.slice(1, -1);
  address = address.split("%")[0]; // zone id
  // An embedded IPv4 tail ("::ffff:192.0.2.1") becomes two groups.
  const v4 = /^(.*:)(\d{1,3}(?:\.\d{1,3}){3})$/.exec(address);
  if (v4) {
    if (!isIPv4(v4[2])) return undefined;
    const [a, b, c, d] = v4[2].split(".").map(Number);
    address = `${v4[1]}${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  if (!/^[0-9a-f:]+$/.test(address) || !address.includes(":")) return undefined;
  const halves = address.split("::");
  if (halves.length > 2) return undefined;
  const parse = (part: string) => (part === "" ? [] : part.split(":"));
  const head = parse(halves[0]);
  const tail = halves.length === 2 ? parse(halves[1]) : [];
  if ([...head, ...tail].some((group) => !/^[0-9a-f]{1,4}$/.test(group))) return undefined;
  const count = head.length + tail.length;
  if (halves.length === 1 ? count !== 8 : count > 7) return undefined;
  const zeros: string[] = new Array(halves.length === 2 ? 8 - count : 0).fill("0");
  return [...head, ...zeros, ...tail].map((group) => parseInt(group, 16));
}

/**
 * The address the rate limit counts: IPv4 as is, IPv4-mapped IPv6 as IPv4,
 * and IPv6 by its /64 (a single device or home usually holds a whole /64).
 */
export function ipBucket(text: string): string | undefined {
  const value = text.trim();
  if (isIPv4(value)) return value;
  const groups = ipv6Groups(value);
  if (!groups) return undefined;
  if (groups.slice(0, 5).every((g) => g === 0) && groups[5] === 0xffff) {
    return [groups[6] >> 8, groups[6] & 0xff, groups[7] >> 8, groups[7] & 0xff].join(".");
  }
  return groups.slice(0, 4).map((g) => g.toString(16)).join(":") + "::/64";
}

/**
 * The caller's address. Supabase's edge sits behind Cloudflare, which sets
 * cf-connecting-ip itself; otherwise the last x-forwarded-for entry is the one
 * the platform appended (earlier entries are whatever the client sent).
 * Verify on the live project with backend/README.md's "Abuse runbook".
 */
export function clientIp(headers: Headers): string | undefined {
  const cloudflare = headers.get("cf-connecting-ip");
  if (cloudflare) {
    const bucket = ipBucket(cloudflare);
    if (bucket) return bucket;
  }
  const forwarded = headers.get("x-forwarded-for")?.split(",").map((part) => part.trim()).filter(Boolean);
  const last = forwarded?.at(-1);
  return last ? ipBucket(last) : undefined;
}
