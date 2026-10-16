// Short-lived, signed picture URLs for polls. A URL names the poll, the side
// and when it stops working, with an HMAC-SHA256 (truncated to 128 bits) over
// all three, keyed by the service role key, which only the server holds:
// nobody can make one, change its side or stretch its time. It still needs
// the anon key at the gateway, and the poll must still be live when it's
// loaded. URLs stay the same within an hour (they end on the next full hour
// but one, or when the poll ends), so browsers can cache the pictures.

const LABEL = "aybuke polls picture v1";
const encoder = new TextEncoder();

export const POLL_ID_PATTERN = /^[A-Za-z0-9_-]{16}$/;
const SIGNATURE_PATTERN = /^[A-Za-z0-9_-]{22}$/;

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function signingKey(secret: string): Promise<CryptoKey> {
  if (!secret) throw new Error("no signing secret");
  return await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
}

export async function pictureSignature(key: CryptoKey, pollId: string, side: string, expires: number): Promise<string> {
  const message = encoder.encode(`${LABEL}\n${pollId}\n${side}\n${expires}`);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, message));
  return base64url(mac.subarray(0, 16));
}

/** When a picture URL made now stops working (Unix seconds): the next full hour but one, or the poll's end. */
export function urlExpiry(now: Date, pollEnds: Date): number {
  const hour = 3600;
  const bucket = (Math.floor(now.getTime() / 1000 / hour) + 2) * hour;
  return Math.min(bucket, Math.floor(pollEnds.getTime() / 1000));
}

export async function pictureUrl(
  key: CryptoKey,
  base: string,
  pollId: string,
  side: "a" | "b",
  expires: number,
): Promise<string> {
  const signature = await pictureSignature(key, pollId, side, expires);
  return `${base}/image?id=${pollId}&side=${side}&exp=${expires}&sig=${signature}`;
}

export type UrlCheck = { ok: true; pollId: string; side: "a" | "b"; expires: number } | {
  ok: false;
  reason: "malformed" | "expired" | "bad_signature";
};

/** A picture URL's query, checked: well formed, not expired, signed by us (compared in constant time). */
export async function checkPictureUrl(key: CryptoKey, params: URLSearchParams, now: Date): Promise<UrlCheck> {
  const pollId = params.get("id") ?? "";
  const side = params.get("side") ?? "";
  const exp = params.get("exp") ?? "";
  const sig = params.get("sig") ?? "";
  if (!POLL_ID_PATTERN.test(pollId) || (side !== "a" && side !== "b") || !/^\d{1,12}$/.test(exp)) {
    return { ok: false, reason: "malformed" };
  }
  if (!SIGNATURE_PATTERN.test(sig)) return { ok: false, reason: "malformed" };
  const expires = Number(exp);
  if (expires * 1000 <= now.getTime()) return { ok: false, reason: "expired" };
  const expected = encoder.encode(await pictureSignature(key, pollId, side, expires));
  const given = encoder.encode(sig);
  let difference = expected.length ^ given.length;
  for (let i = 0; i < expected.length; i++) difference |= expected[i] ^ (given[i] ?? 0);
  if (difference !== 0) return { ok: false, reason: "bad_signature" };
  return { ok: true, pollId, side, expires };
}
