// Verifies StoreKit 2 signed data (JWS) with Apple's official library, so Pro
// status, credit packs and free credits never rely on what the client claims.
//
//   * Transactions (Pro, credit packs): Production and Sandbox, with Apple's
//     online revocation checks. Xcode-signed (local StoreKit testing)
//     transactions are never accepted.
//   * AppTransactions (free credits, see installs in the 20261021 migration):
//     Production (App Store) and Sandbox (TestFlight and App Review), checked
//     against Apple Root CA G3 for the bundle id. Offline checks only, the way
//     StoreKit itself verifies them, so an OCSP hiccup at Apple can't switch
//     free credits off for everyone. The Xcode environment is signed by a local
//     certificate, so it's accepted only with GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS
//     set on a local backend, never on a hosted project.
//   * App Store Server Notifications V2 (refunds, revocations): verified like
//     transactions, by the same verifiers.
import { Buffer } from "node:buffer";
import {
  type AppTransaction,
  Environment,
  type JWSTransactionDecodedPayload,
  OfferDiscountType,
  OfferType,
  type ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";

export const PRO_PRODUCTS = new Set(["app.glowlit.pro.monthly", "app.glowlit.pro.yearly"]);
export const YEARLY_PRODUCT = "app.glowlit.pro.yearly";
export const CREDIT_PACKS: Record<string, number> = {
  "app.glowlit.credits.30": 30,
  "app.glowlit.credits.100": 100,
};

// Apple Root CA G3 only: the root of the StoreKit signing chain. G2 is not trusted.
export const ROOT_CERTIFICATE_URLS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
];

interface Env {
  get(name: string): string | undefined;
}

let rootsPromise: Promise<Buffer[]> | undefined;

function appleRoots(): Promise<Buffer[]> {
  rootsPromise ??= Promise.all(ROOT_CERTIFICATE_URLS.map(async (url) => {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Couldn't download ${url}`);
    return Buffer.from(await response.arrayBuffer());
  })).catch((error) => {
    rootsPromise = undefined; // try again on the next request
    throw error;
  });
  return rootsPromise;
}

function bundleId(env: Env): string {
  return env.get("APPLE_BUNDLE_ID") ?? "app.glowlit.ios";
}

/** The numeric App Store app id, needed to verify anything from the App Store itself. */
function appAppleId(env: Env): number | undefined {
  const id = Number(env.get("APPLE_APP_ID") ?? "");
  return Number.isFinite(id) && id > 0 ? id : undefined;
}

let verifiersPromise: Promise<SignedDataVerifier[]> | undefined;

async function makeVerifiers(env: Env, loadRoots: () => Promise<Buffer[]>): Promise<SignedDataVerifier[]> {
  const roots = await loadRoots();
  const list: SignedDataVerifier[] = [];
  const appId = appAppleId(env);
  // Production verification needs the numeric App Store app id (set APPLE_APP_ID).
  if (appId) list.push(new SignedDataVerifier(roots, true, Environment.PRODUCTION, bundleId(env), appId));
  // Sandbox covers TestFlight and sandbox testers. Xcode-signed (local
  // StoreKit testing) transactions are deliberately NOT accepted.
  list.push(new SignedDataVerifier(roots, true, Environment.SANDBOX, bundleId(env)));
  return list;
}

function verifiers(): Promise<SignedDataVerifier[]> {
  verifiersPromise ??= makeVerifiers(Deno.env, appleRoots).catch((error) => {
    verifiersPromise = undefined;
    throw error;
  });
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
 * The yearly plan's 7-day free trial. Apple marks it with offerDiscountType
 * FREE_TRIAL; transactions from before that field existed only say it's an
 * introductory offer, which on the yearly plan is the trial (the monthly
 * plan's introductory offer is the paid $1.99 month).
 */
export function isFreeTrial(
  transaction: Pick<JWSTransactionDecodedPayload, "offerType" | "offerDiscountType" | "productId">,
): boolean {
  if (transaction.offerDiscountType) return transaction.offerDiscountType === OfferDiscountType.FREE_TRIAL;
  // Depends on App Store Connect: the yearly plan has only the 7-day free trial as an introductory offer.
  return transaction.offerType === OfferType.INTRODUCTORY_OFFER && transaction.productId === YEARLY_PRODUCT;
}

export interface EntitlementStatus {
  isPro: boolean;
  isTrial: boolean;
}

/**
 * Pro status for this request. A verified, unexpired entitlement already bound
 * to the user wins; otherwise the `X-Entitlement-JWS` header is verified and
 * bound to the user (moving it away from any previous anonymous account, so a
 * subscription can't be shared across accounts at the same time; its credits
 * move with it). The trial flag is stored for the credit grant: a trial's
 * entitlement expires when the trial ends, and the paid renewal read then is
 * no longer a trial.
 */
export async function resolveEntitlement(
  db: SupabaseClient,
  userId: string,
  jws: string | null,
): Promise<EntitlementStatus> {
  const now = new Date().toISOString();
  const { data: active } = await db
    .from("entitlements")
    .select("original_transaction_id, is_trial")
    .eq("user_id", userId)
    .eq("revoked", false)
    .gt("expires_at", now)
    .order("expires_at", { ascending: false })
    .limit(1);
  if (active && active.length > 0) {
    return { isPro: true, isTrial: Boolean((active[0] as { is_trial: boolean | null }).is_trial) };
  }
  if (!jws) return { isPro: false, isTrial: false };

  try {
    const transaction = await verifyTransaction(jws);
    if (!transaction.productId || !PRO_PRODUCTS.has(transaction.productId) || !transaction.originalTransactionId) {
      return { isPro: false, isTrial: false };
    }
    const expiresAt = transaction.expiresDate ? new Date(transaction.expiresDate) : undefined;
    const revoked = Boolean(transaction.revocationDate);
    const isTrial = isFreeTrial(transaction);
    const { data: saved, error: saveError } = await db.rpc("record_entitlement", {
      p_user: userId,
      p_original_transaction_id: transaction.originalTransactionId,
      p_product_id: transaction.productId,
      p_expires_at: expiresAt?.toISOString() ?? null,
      p_revoked: revoked,
      p_environment: String(transaction.environment ?? ""),
      p_is_trial: isTrial,
    });
    if (saveError) console.warn("entitlement not saved", saveError.message);
    // The stored transaction is newer than this one: it grants nothing here.
    if (!saveError && saved === false) return { isPro: false, isTrial: false };
    const isPro = !revoked && !!expiresAt && expiresAt.getTime() > Date.now();
    return { isPro, isTrial: isPro && isTrial };
  } catch (error) {
    console.warn("entitlement verification failed", error instanceof Error ? error.message : error);
    return { isPro: false, isTrial: false };
  }
}

// MARK: - App Store installs (AppTransaction)

/** What the request proved about its App Store install. */
export type InstallProof =
  | { status: "verified"; appTransactionId?: string; environment: string }
  | { status: "missing" }
  | { status: "invalid"; reason: string };

/** A JWS of three base64url parts, small enough to be an AppTransaction. */
const JWS_PATTERN = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/;
const MAX_JWS_LENGTH = 16_384;

/**
 * Local StoreKit testing in Xcode signs with a certificate on the Mac, which
 * proves nothing. Only for a backend running on this machine, and only when
 * asked for.
 */
export function xcodeAllowed(env: Env = Deno.env): boolean {
  if (env.get("GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS") !== "true") return false;
  let host = "";
  try {
    host = new URL(env.get("SUPABASE_URL") ?? "").hostname;
  } catch {
    return false;
  }
  const local = ["localhost", "127.0.0.1", "[::1]", "::1", "kong", "host.docker.internal"].includes(host) ||
    host.endsWith(".localhost") || host.endsWith(".local");
  if (!local) console.error("GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS is ignored on a hosted project:", host);
  return local;
}

export interface InstallVerifierOptions {
  env?: Env;
  /** Apple's root certificates (DER). Defaults to downloading them once. */
  roots?: () => Promise<Buffer[]>;
}

let installVerifiersPromise: Promise<SignedDataVerifier[]> | undefined;

async function makeInstallVerifiers(options: InstallVerifierOptions): Promise<SignedDataVerifier[]> {
  const env = options.env ?? Deno.env;
  const roots = await (options.roots ?? appleRoots)();
  const id = bundleId(env);
  const list: SignedDataVerifier[] = [];
  const appId = appAppleId(env);
  if (appId) list.push(new SignedDataVerifier(roots, false, Environment.PRODUCTION, id, appId));
  // TestFlight and App Review run in the sandbox: rejecting it would fail every
  // AI feature during review (Guideline 2.1).
  list.push(new SignedDataVerifier(roots, false, Environment.SANDBOX, id));
  if (xcodeAllowed(env)) list.push(new SignedDataVerifier([], false, Environment.XCODE, id));
  return list;
}

function installVerifiers(options: InstallVerifierOptions): Promise<SignedDataVerifier[]> {
  if (options.env || options.roots) return makeInstallVerifiers(options);
  installVerifiersPromise ??= makeInstallVerifiers(options).catch((error) => {
    installVerifiersPromise = undefined;
    throw error;
  });
  return installVerifiersPromise;
}

/** A JWS's payload, unverified: only to explain a rejection. */
function unverifiedPayload(jws: string): Record<string, unknown> | undefined {
  try {
    const payload: unknown = JSON.parse(atob(jws.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload && typeof payload === "object" ? payload as Record<string, unknown> : undefined;
  } catch {
    return undefined;
  }
}

/** The environment a JWS claims, unverified: only to explain a rejection in the logs. */
function claimedEnvironment(jws: string): string | undefined {
  const receiptType = unverifiedPayload(jws)?.receiptType;
  return typeof receiptType === "string" ? receiptType : undefined;
}

/**
 * Checks the `X-App-Transaction` header: StoreKit's signed AppTransaction for
 * this install, verified for the bundle id in Production or Sandbox. The
 * appTransactionId it carries (back-deployed to iOS 15 by Apple) is one value
 * per Apple Account and app, the same on every device and reinstall.
 */
export async function verifyInstall(jws: string | null, options: InstallVerifierOptions = {}): Promise<InstallProof> {
  const value = jws?.trim() ?? "";
  if (!value) return { status: "missing" };
  if (value.length > MAX_JWS_LENGTH || !JWS_PATTERN.test(value)) return { status: "invalid", reason: "malformed" };

  let list: SignedDataVerifier[];
  try {
    list = await installVerifiers(options);
  } catch (error) {
    // Apple's root certificates couldn't be loaded: not the client's fault,
    // but nothing can be verified either (fail closed: no free credits).
    console.error("AppTransaction verifiers unavailable", error instanceof Error ? error.message : error);
    return { status: "invalid", reason: "verifier_unavailable" };
  }
  let lastError = "no verifier";
  for (const verifier of list) {
    try {
      const transaction: AppTransaction = await verifier.verifyAndDecodeAppTransaction(value);
      const appTransactionId = typeof transaction.appTransactionId === "string" && transaction.appTransactionId
        ? transaction.appTransactionId
        : undefined;
      return { status: "verified", appTransactionId, environment: String(transaction.receiptType ?? "") };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
  }
  const claimed = claimedEnvironment(value);
  if (claimed === Environment.PRODUCTION && !appAppleId(options.env ?? Deno.env)) {
    console.error("an App Store AppTransaction arrived, but APPLE_APP_ID isn't set: free credits stay off until it is");
  } else {
    console.warn("AppTransaction rejected", claimed ?? "unknown environment", lastError);
  }
  return { status: "invalid", reason: claimed === Environment.XCODE ? "xcode" : "unverified" };
}

// MARK: - App Store Server Notifications V2

/** A notification Apple signed for this app, with the transaction it's about when it names one. */
export interface VerifiedNotification {
  notification: ResponseBodyV2DecodedPayload;
  transaction?: JWSTransactionDecodedPayload;
}

/**
 * A notification that wasn't accepted. `retryable` when the fault is ours
 * (Apple's roots or revocation check unreachable, APPLE_APP_ID missing), so
 * Apple should send it again; otherwise it isn't Apple's, or not for this app.
 */
export class NotificationRejected extends Error {
  constructor(message: string, readonly retryable: boolean) {
    super(message);
  }
}

export interface NotificationVerifierOptions {
  env?: Env;
  /** Apple's root certificates (DER). Defaults to downloading them once. */
  roots?: () => Promise<Buffer[]>;
  /** Tests only: the verifiers to try, in place of Production and Sandbox. */
  verifiers?: SignedDataVerifier[];
}

// A notification carries a signed transaction and renewal, each with its certificate chain.
const MAX_NOTIFICATION_LENGTH = 262_144;

function describe(error: unknown): string {
  if (error instanceof VerificationException) return VerificationStatus[error.status] ?? String(error.status);
  return error instanceof Error ? error.message : String(error);
}

function isRetryable(error: unknown): boolean {
  return error instanceof VerificationException && error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE;
}

/**
 * Verifies an App Store Server Notification V2 `signedPayload` the way
 * transactions are verified: Apple Root CA G3 only, online revocation checks,
 * this bundle id, Production (with APPLE_APP_ID) or Sandbox. The transaction
 * inside is verified by the verifier that accepted the notification, so both
 * are Apple's and from the same environment.
 */
export async function verifyNotification(
  signedPayload: unknown,
  options: NotificationVerifierOptions = {},
): Promise<VerifiedNotification> {
  if (
    typeof signedPayload !== "string" || signedPayload.length > MAX_NOTIFICATION_LENGTH ||
    !JWS_PATTERN.test(signedPayload)
  ) {
    throw new NotificationRejected("malformed", false);
  }
  const env = options.env ?? Deno.env;
  let list: SignedDataVerifier[];
  try {
    list = options.verifiers ??
      (options.env || options.roots ? await makeVerifiers(env, options.roots ?? appleRoots) : await verifiers());
  } catch (error) {
    console.error("notification verifiers unavailable", describe(error));
    throw new NotificationRejected("verifier_unavailable", true);
  }

  let retryable = false;
  let lastError = "no verifier";
  for (const verifier of list) {
    let notification: ResponseBodyV2DecodedPayload;
    try {
      notification = await verifier.verifyAndDecodeNotification(signedPayload);
    } catch (error) {
      retryable ||= isRetryable(error);
      lastError = describe(error);
      continue;
    }
    const signedTransaction = notification.data?.signedTransactionInfo;
    if (!signedTransaction) return { notification };
    try {
      return { notification, transaction: await verifier.verifyAndDecodeTransaction(signedTransaction) };
    } catch (error) {
      throw new NotificationRejected(`transaction ${describe(error)}`, isRetryable(error));
    }
  }

  const data = unverifiedPayload(signedPayload)?.data as { environment?: unknown } | undefined;
  if (data?.environment === Environment.PRODUCTION && !appAppleId(env)) {
    console.error("an App Store notification arrived, but APPLE_APP_ID isn't set: it waits for Apple's retry");
    throw new NotificationRejected("app_id_missing", true);
  }
  throw new NotificationRejected(lastError, retryable);
}
