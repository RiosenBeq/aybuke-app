// deno test _shared/
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import {
  checkImage,
  clientIp,
  ipBucket,
  MAX_IMAGE_BYTES,
  MAX_PROMPT_CHARS,
  promptLength,
  sanitizePrompt,
  sniffType,
} from "./input.ts";

const uri = (mime: string, bytes: Uint8Array) => `data:${mime};base64,${Buffer.from(bytes).toString("base64")}`;

/** A minimal JPEG: SOI, an APP0 segment, then a baseline frame header. */
function jpeg(width: number, height: number, padding = 0): Uint8Array {
  const app0 = [
    0xff,
    0xe0,
    0x00,
    0x10,
    0x4a,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
  ];
  const comment = padding > 0
    ? [0xff, 0xfe, (padding + 2) >> 8, (padding + 2) & 0xff, ...new Array(padding).fill(0x20)]
    : [];
  const sof = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03];
  return new Uint8Array([0xff, 0xd8, ...app0, ...comment, ...sof, ...new Array(20).fill(0), 0xff, 0xd9]);
}

function png(width: number, height: number): Uint8Array {
  const b = new Uint8Array(33);
  b.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  new DataView(b.buffer).setUint32(16, width);
  new DataView(b.buffer).setUint32(20, height);
  return b;
}

function webpVP8X(width: number, height: number): Uint8Array {
  const b = new Uint8Array(30);
  b.set([..."RIFF"].map((c) => c.charCodeAt(0)), 0);
  b.set([..."WEBPVP8X"].map((c) => c.charCodeAt(0)), 8);
  const w = width - 1;
  const h = height - 1;
  b.set([w & 0xff, (w >> 8) & 0xff, (w >> 16) & 0xff, h & 0xff, (h >> 8) & 0xff, (h >> 16) & 0xff], 24);
  return b;
}

function heic(width: number, height: number): Uint8Array {
  const b = new Uint8Array(64);
  b.set([0, 0, 0, 24, ..."ftypheic".split("").map((c) => c.charCodeAt(0))], 0);
  b.set([0, 0, 0, 20, ..."ispe".split("").map((c) => c.charCodeAt(0)), 0, 0, 0, 0], 32);
  new DataView(b.buffer).setUint32(44, width);
  new DataView(b.buffer).setUint32(48, height);
  return b;
}

Deno.test("prompts: what the provider sees, and the cap", () => {
  assert.equal(sanitizePrompt("  pink\u200b hair\n\nplease\u202e  "), "pink hair please");
  assert.equal(sanitizePrompt("ｐｉｎｋ\u0007hair"), "pink hair");
  assert.equal(sanitizePrompt("bow\ufe0f emoji"), "bow emoji");
  assert.equal(promptLength("ab🎀"), 3);
  // The app's longest: 800 characters, the edit guard and "Only edit me".
  assert.ok(800 + 200 + 90 < MAX_PROMPT_CHARS);
});

Deno.test("images: supported types with readable dimensions", () => {
  const ok = (value: string) => {
    const check = checkImage(value);
    assert.ok(check.ok, JSON.stringify(check));
    return check.info;
  };
  assert.deepEqual(ok(uri("image/jpeg", jpeg(1536, 1024))), {
    type: "jpeg",
    width: 1536,
    height: 1024,
    bytes: jpeg(1536, 1024).length,
  });
  assert.equal(ok(uri("image/jpg", jpeg(800, 600))).width, 800);
  assert.equal(ok(uri("image/png", png(1024, 1536))).height, 1536);
  assert.equal(ok(uri("image/webp", webpVP8X(640, 480))).width, 640);
  assert.equal(ok(uri("image/heic", heic(3024, 4032))).height, 4032);
  // A frame header after unusually large metadata is still found.
  assert.equal(ok(uri("image/jpeg", jpeg(1200, 900, 60_000))).width, 1200);
  assert.equal(sniffType(png(1, 1)), "png");
});

Deno.test("images: anything else is refused, closed", () => {
  const refused = (value: unknown, code = "image_invalid") => {
    const check = checkImage(value);
    assert.ok(!check.ok && check.code === code, JSON.stringify(check));
  };
  refused(undefined);
  refused("https://example.com/a.jpg");
  refused("data:image/gif;base64,R0lGODlhAQABAAAAACw=");
  refused("data:image/jpeg;base64,not base64!");
  refused(uri("image/png", jpeg(100, 100))); // labelled PNG, really JPEG
  refused(uri("image/jpeg", new TextEncoder().encode("<svg xmlns='http://www.w3.org/2000/svg'/>")));
  refused(uri("image/jpeg", jpeg(5000, 1000))); // too wide
  refused(uri("image/png", png(8, 8))); // too small
  refused(uri("image/jpeg", new Uint8Array([0xff, 0xd8, 0xff, 0xd9]))); // no frame
  const huge = "data:image/jpeg;base64," + "A".repeat(Math.ceil((MAX_IMAGE_BYTES + 3) / 3) * 4);
  refused(huge, "too_large");
});

Deno.test("client address: the last forwarded hop, never a client's cf-connecting-ip", () => {
  assert.equal(
    clientIp(new Headers({ "cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "1.2.3.4, 198.51.100.7" })),
    "198.51.100.7",
    "cf-connecting-ip is ignored",
  );
  assert.equal(
    clientIp(new Headers({ "x-forwarded-for": "6.6.6.6, 198.51.100.7" })),
    "198.51.100.7",
    "a spoofed first entry",
  );
  assert.equal(
    clientIp(new Headers({ "x-forwarded-for": " 1.2.3.4 , 198.51.100.7 , " })),
    "198.51.100.7",
    "spaces and empty entries",
  );
  assert.equal(
    clientIp(new Headers({ "x-forwarded-for": "6.6.6.6, 2001:db8:85a3:8d3:1319:8a2e:370:7348" })),
    "2001:db8:85a3:8d3::/64",
  );
  assert.equal(clientIp(new Headers({ "cf-connecting-ip": "203.0.113.9" })), undefined);
  assert.equal(clientIp(new Headers({})), undefined);
  assert.equal(clientIp(new Headers({ "x-forwarded-for": "not-an-ip" })), undefined);
  assert.equal(clientIp(new Headers({ "x-forwarded-for": "198.51.100.7, not-an-ip" })), undefined);
  assert.equal(ipBucket("2001:db8:85a3:8d3:1319:8a2e:370:7348"), "2001:db8:85a3:8d3::/64");
  assert.equal(ipBucket("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(ipBucket("::ffff:192.0.2.1"), "192.0.2.1");
  assert.equal(ipBucket("[2001:db8::1]"), "2001:db8:0:0::/64");
  assert.equal(ipBucket("256.1.1.1"), undefined);
  assert.equal(ipBucket("1:2:3"), undefined);
});
