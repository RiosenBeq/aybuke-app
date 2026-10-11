// Verifies StoreKit 2 signed transactions (JWS) with Apple's official library,
// so Pro status and credit packs never rely on what the client claims.
import { Buffer } from "node:buffer";
import {
  Environment,
  type JWSTransactionDecodedPayload,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";

export const PRO_PRODUCTS = new Set(["app.glowlit.pro.monthly", "app.glowlit.pro.yearly"]);
export const CREDIT_PACKS: Record<string, number> = {
  "app.glowlit.credits.30": 30,
  "app.glowlit.credits.100": 100,
};

const ROOT_CERTIFICATE_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
];

let verifiersPromise: Promise<SignedDataVerifier[]> | undefined;

function verifiers(): Promise<SignedDataVerifier[]> {
  verifiersPromise ??= (async () => {
    const roots = await Promise.all(ROOT_CERTIFICATE_URLS.map(async (url) => {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Couldn't download ${url}`);
      return Buffer.from(await response.arrayBuffer());
    }));
    const bundleId = Deno.env.get("APPLE_BUNDLE_ID") ?? "app.glowlit.ios";
    const appAppleId = Number(Deno.env.get("APPLE_APP_ID") ?? "");
    const list: SignedDataVerifier[] = [];
    // Production verification needs the numeric App Store app id (set APPLE_APP_ID).
    if (Number.isFinite(appAppleId) && appAppleId > 0) {
      list.push(new SignedDataVerifier(roots, true, Environment.PRODUCTION, bundleId, appAppleId));
    }
    // Sandbox covers TestFlight and sandbox testers. Xcode-signed (local
    // StoreKit testing) transactions are deliberately NOT accepted.
    list.push(new SignedDataVerifier(roots, true, Environment.SANDBOX, bundleId));
    return list;
  })();
  return verifiersPromise;
}

export async function verifyTransaction(jws: string): Promise<JWSTransactionDecodedPayload> {
  let lastError: unknown;
  for (const verifier of await verifiers()) {
    try {
      return await verifier.verifyAndDecodeTransaction(jws);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? new Error("No verifier available");
}

/**
 * Pro status for this request. A verified, unexpired entitlement already bound
 * to the user wins; otherwise the `X-Entitlement-JWS` header is verified and
 * bound to the user (moving it away from any previous anonymous account, so a
 * subscription can't be shared across accounts at the same time).
 */
export async function resolveEntitlement(db: SupabaseClient, userId: string, jws: string | null): Promise<boolean> {
  const now = new Date().toISOString();
  const { data: active } = await db
    .from("entitlements")
    .select("original_transaction_id")
    .eq("user_id", userId)
    .eq("revoked", false)
    .gt("expires_at", now)
    .limit(1);
  if (active && active.length > 0) return true;
  if (!jws) return false;

  try {
    const transaction = await verifyTransaction(jws);
    if (!transaction.productId || !PRO_PRODUCTS.has(transaction.productId) || !transaction.originalTransactionId) {
      return false;
    }
    const expiresAt = transaction.expiresDate ? new Date(transaction.expiresDate) : undefined;
    const revoked = Boolean(transaction.revocationDate);
    await db.from("entitlements").upsert({
      original_transaction_id: transaction.originalTransactionId,
      user_id: userId,
      product_id: transaction.productId,
      expires_at: expiresAt?.toISOString() ?? null,
      revoked,
      environment: String(transaction.environment ?? ""),
      updated_at: now,
    });
    return !revoked && !!expiresAt && expiresAt.getTime() > Date.now();
  } catch (error) {
    console.warn("entitlement verification failed", error instanceof Error ? error.message : error);
    return false;
  }
}
