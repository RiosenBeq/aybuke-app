// AdMob rewarded ads: server-side verification (SSV) of reward callbacks.
// https://developers.google.com/admob/ios/ssv
//
// AdMob calls our callback URL with a GET query string whose last two
// parameters are `signature` and `key_id`. The signature is ECDSA P-256 with
// SHA-256 (DER, URL-safe base64) over the query string up to, but not
// including, "&signature=". Google publishes the public keys at
// VERIFIER_KEYS_URL; they're cached here (Google: never longer than 24 hours)
// and fetched again when a callback names a key id we don't know.
//
// Fail-closed: anything that doesn't verify throws, and no credit is granted.

export const VERIFIER_KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";

/** Well under Google's 24-hour limit. */
const KEY_CACHE_MS = 12 * 60 * 60 * 1000;
/** An unknown key id refetches the keys, but not more than once a minute. */
const UNKNOWN_KEY_REFETCH_MS = 60 * 1000;
const SIGNATURE_MARKER = "&signature=";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class VerificationError extends Error {}

/** The parameters of a verified callback. */
export interface RewardCallback {
  adNetwork: string;
  /** The ad unit's id as AdMob sends it: the number after the slash. */
  adUnit: string;
  /** Our single-use reward token (a UUID), set as the SSV custom data. */
  customData: string;
  keyId: string;
  rewardAmount: number;
  rewardItem: string;
  /** When the reward was earned, in milliseconds since 1970. */
  timestamp: number;
  transactionId: string;
}

type KeysFetcher = () => Promise<unknown>;

/** Google's verifier keys by key id, cached. Inject `fetchKeys` and `now` in tests. */
export class VerifierKeys {
  private keys = new Map<string, CryptoKey>();
  private fetchedAt = -Infinity;
  private pending: Promise<void> | undefined;

  constructor(
    private readonly fetchKeys: KeysFetcher = defaultFetchKeys,
    private readonly now: () => number = Date.now,
  ) {}

  async key(keyId: string): Promise<CryptoKey> {
    const age = this.now() - this.fetchedAt;
    if (age >= KEY_CACHE_MS || (!this.keys.has(keyId) && age >= UNKNOWN_KEY_REFETCH_MS)) {
      await this.refresh();
    }
    const key = this.keys.get(keyId);
    if (!key) throw new VerificationError(`Unknown AdMob key id ${keyId}.`);
    return key;
  }

  private refresh(): Promise<void> {
    this.pending ??= (async () => {
      try {
        this.keys = await importVerifierKeys(await this.fetchKeys());
        this.fetchedAt = this.now();
      } finally {
        this.pending = undefined;
      }
    })();
    return this.pending;
  }
}

async function defaultFetchKeys(): Promise<unknown> {
  const response = await fetch(VERIFIER_KEYS_URL);
  if (!response.ok) throw new Error(`AdMob verifier keys answered ${response.status}.`);
  return await response.json();
}

/** `{ "keys": [{ "keyId": 3335741209, "pem": "…", "base64": "<SPKI>" }] }` → keys by id. */
export async function importVerifierKeys(json: unknown): Promise<Map<string, CryptoKey>> {
  const entries = (json as { keys?: unknown })?.keys;
  if (!Array.isArray(entries)) throw new Error("AdMob verifier keys have no `keys` list.");
  const keys = new Map<string, CryptoKey>();
  for (const entry of entries as { keyId?: unknown; base64?: unknown }[]) {
    if ((typeof entry?.keyId !== "number" && typeof entry?.keyId !== "string") || typeof entry?.base64 !== "string") {
      continue;
    }
    const key = await crypto.subtle.importKey(
      "spki",
      base64Decode(entry.base64),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    keys.set(String(entry.keyId), key);
  }
  if (keys.size === 0) throw new Error("AdMob verifier keys list is empty.");
  return keys;
}

/**
 * Splits a raw query string into the signed content and the signature and
 * key id that follow it. `rawQuery` is everything after "?", untouched.
 */
export function splitSignedQuery(rawQuery: string): { content: string; signature: string; keyId: string } {
  const at = rawQuery.indexOf(SIGNATURE_MARKER);
  if (at <= 0) throw new VerificationError("The callback has no signature.");
  const tail = new URLSearchParams(rawQuery.slice(at + 1));
  const signature = tail.get("signature") ?? "";
  const keyId = tail.get("key_id") ?? "";
  if (
    !signature || !/^\d+$/.test(keyId) || [...tail.keys()].some((name) => name !== "signature" && name !== "key_id")
  ) {
    throw new VerificationError("The callback's signature or key id is malformed.");
  }
  return { content: rawQuery.slice(0, at), signature, keyId };
}

/**
 * Verifies an AdMob SSV callback and returns its parameters. Google's own
 * sample checks the percent-decoded query (Java's `URI.getQuery()`), so the
 * decoded form is tried too when the raw one has escapes; both are bound to
 * Google's signature, so neither can be forged.
 */
export async function verifyCallback(rawQuery: string, keys: VerifierKeys): Promise<RewardCallback> {
  const { content, signature, keyId } = splitSignedQuery(rawQuery);
  const key = await keys.key(keyId);
  let raw: Uint8Array<ArrayBuffer>;
  try {
    raw = derToRaw(base64Decode(signature));
  } catch {
    throw new VerificationError("The callback's signature isn't a valid ECDSA signature.");
  }
  const candidates = [content];
  if (content.includes("%")) {
    try {
      candidates.push(decodeURIComponent(content));
    } catch {
      // Malformed escapes: only the raw form can match.
    }
  }
  let verified = false;
  for (const candidate of candidates) {
    if (
      await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        raw,
        new TextEncoder().encode(candidate),
      )
    ) {
      verified = true;
      break;
    }
  }
  if (!verified) throw new VerificationError("The callback's signature doesn't match.");
  return parseCallback(content, keyId);
}

function parseCallback(content: string, keyId: string): RewardCallback {
  const params = new URLSearchParams(content);
  const transactionId = params.get("transaction_id") ?? "";
  const adUnit = params.get("ad_unit") ?? "";
  const customData = params.get("custom_data") ?? "";
  const rewardAmount = Number(params.get("reward_amount") ?? "");
  const timestamp = Number(params.get("timestamp") ?? "");
  if (!/^[0-9A-Za-z_-]{1,128}$/.test(transactionId)) throw new VerificationError("Missing or odd transaction id.");
  if (!adUnit) throw new VerificationError("Missing ad unit.");
  if (!Number.isFinite(rewardAmount) || !Number.isFinite(timestamp)) {
    throw new VerificationError("Missing reward amount or timestamp.");
  }
  return {
    adNetwork: params.get("ad_network") ?? "",
    adUnit,
    customData,
    keyId,
    rewardAmount,
    rewardItem: params.get("reward_item") ?? "",
    timestamp,
    transactionId,
  };
}

/** Our reward tokens are UUIDs; anything else isn't ours. */
export function isRewardToken(value: string): boolean {
  return UUID_PATTERN.test(value);
}

/**
 * Whether `adUnit` (as AdMob sends it, the number after the slash) is one of
 * ours. `allowList` is ADMOB_REWARDED_AD_UNIT: comma-separated full ids
 * ("ca-app-pub-123/456") or bare unit numbers. Empty allows nothing.
 */
export function adUnitAllowed(adUnit: string, allowList: string | undefined): boolean {
  const unit = adUnit.trim().split("/").pop() ?? "";
  if (!unit) return false;
  return (allowList ?? "")
    .split(",")
    .map((entry) => entry.trim().split("/").pop() ?? "")
    .some((allowed) => allowed !== "" && allowed === unit);
}

/** Standard or URL-safe base64, with or without padding. */
export function base64Decode(text: string): Uint8Array<ArrayBuffer> {
  const normalized = text.trim().replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

/** A DER ECDSA signature (SEQUENCE of two INTEGERs) → the raw r‖s form Web Crypto verifies. */
export function derToRaw(der: Uint8Array, size = 32): Uint8Array<ArrayBuffer> {
  let offset = 0;
  const readLength = (): number => {
    const first = der[offset++];
    if (first === undefined) throw new Error("Truncated DER.");
    if (first < 0x80) return first;
    const count = first & 0x7f;
    if (count === 0 || count > 2) throw new Error("Unsupported DER length.");
    let length = 0;
    for (let index = 0; index < count; index++) {
      const byte = der[offset++];
      if (byte === undefined) throw new Error("Truncated DER.");
      length = (length << 8) | byte;
    }
    return length;
  };
  const readInteger = (): Uint8Array => {
    if (der[offset++] !== 0x02) throw new Error("Expected a DER INTEGER.");
    const length = readLength();
    if (length === 0 || offset + length > der.length) throw new Error("Bad DER INTEGER length.");
    let value = der.subarray(offset, offset + length);
    offset += length;
    while (value.length > 1 && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new Error("DER INTEGER too large.");
    return value;
  };
  if (der[offset++] !== 0x30) throw new Error("Expected a DER SEQUENCE.");
  const sequenceLength = readLength();
  if (offset + sequenceLength !== der.length) throw new Error("Bad DER SEQUENCE length.");
  const r = readInteger();
  const s = readInteger();
  if (offset !== der.length) throw new Error("Trailing bytes after the DER signature.");
  const raw = new Uint8Array(size * 2);
  raw.set(r, size - r.length);
  raw.set(s, size * 2 - s.length);
  return raw;
}

/** The raw r‖s form Web Crypto signs → DER, as AdMob sends it (used by the tests). */
export function rawToDer(raw: Uint8Array): Uint8Array<ArrayBuffer> {
  const half = raw.length / 2;
  const integer = (bytes: Uint8Array): number[] => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start++;
    const value = [...bytes.subarray(start)];
    if (value[0] & 0x80) value.unshift(0);
    return [0x02, value.length, ...value];
  };
  const body = [...integer(raw.subarray(0, half)), ...integer(raw.subarray(half))];
  return new Uint8Array([0x30, body.length, ...body]);
}

/** URL-safe base64 without padding, as AdMob writes signatures (used by the tests). */
export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
