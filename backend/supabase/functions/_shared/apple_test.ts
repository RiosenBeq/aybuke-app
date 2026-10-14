// deno test _shared/
// Production and Sandbox AppTransactions are signed by Apple, so only the
// rules around them can be tested here (Apple's library has its own tests
// for the signature chain). An Xcode-environment JWS is signed by a local
// certificate the library doesn't check, which is exactly why it's refused
// unless the dev flag is set on a local backend.
import assert from "node:assert/strict";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
import {
  isFreeTrial,
  NotificationRejected,
  ROOT_CERTIFICATE_URLS,
  verifyInstall,
  verifyNotification,
  xcodeAllowed,
} from "./apple.ts";

const env = (values: Record<string, string>) => ({ get: (name: string) => values[name] });
const base64url = (value: unknown) =>
  btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function appTransaction(fields: Record<string, unknown>): string {
  const payload = {
    receiptType: "Xcode",
    bundleId: "app.glowlit.ios",
    applicationVersion: "1",
    receiptCreationDate: Date.now(),
    originalPurchaseDate: Date.now(),
    originalApplicationVersion: "1",
    appTransactionId: "704289572311155034",
    ...fields,
  };
  return `${base64url({ alg: "ES256", kid: "Apple_Xcode_Key" })}.${base64url(payload)}.c2lnbmF0dXJl`;
}

const noRoots = () => Promise.resolve([]);
const local = { SUPABASE_URL: "http://127.0.0.1:54321", APPLE_BUNDLE_ID: "app.glowlit.ios" };
const hosted = { SUPABASE_URL: "https://efapupjvidyqhqdevmcu.supabase.co", APPLE_BUNDLE_ID: "app.glowlit.ios" };

Deno.test("the free trial is the yearly plan's FREE_TRIAL offer", () => {
  assert.ok(isFreeTrial({ offerDiscountType: "FREE_TRIAL", offerType: 1, productId: "app.glowlit.pro.yearly" }));
  assert.ok(
    !isFreeTrial({ offerDiscountType: "PAY_UP_FRONT", offerType: 1, productId: "app.glowlit.pro.monthly" }),
    "the $1.99 month is a paid period",
  );
  assert.ok(!isFreeTrial({ offerDiscountType: "PAY_AS_YOU_GO", offerType: 1, productId: "app.glowlit.pro.monthly" }));
  assert.ok(!isFreeTrial({ productId: "app.glowlit.pro.yearly" }), "a renewal");
  // Before offerDiscountType existed, the yearly plan's introductory offer was the trial.
  assert.ok(isFreeTrial({ offerType: 1, productId: "app.glowlit.pro.yearly" }));
  assert.ok(!isFreeTrial({ offerType: 1, productId: "app.glowlit.pro.monthly" }));
  assert.ok(!isFreeTrial({ offerType: 2, productId: "app.glowlit.pro.yearly" }), "a promotional offer isn't the trial");
});

Deno.test("only Apple Root CA G3 anchors the signed data", () => {
  assert.deepEqual(ROOT_CERTIFICATE_URLS, ["https://www.apple.com/certificateauthority/AppleRootCA-G3.cer"]);
});

Deno.test("Xcode AppTransactions only on a local backend with the flag", () => {
  assert.ok(!xcodeAllowed(env(local)), "off by default");
  assert.ok(xcodeAllowed(env({ ...local, GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS: "true" })));
  assert.ok(xcodeAllowed(env({ SUPABASE_URL: "http://kong:8000", GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS: "true" })));
  assert.ok(
    !xcodeAllowed(env({ ...hosted, GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS: "true" })),
    "never on a hosted project",
  );
  assert.ok(!xcodeAllowed(env({ GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS: "true" })), "no URL, no exception");
});

Deno.test("missing, malformed and unverifiable AppTransactions", async () => {
  assert.deepEqual(await verifyInstall(null, { env: env(hosted), roots: noRoots }), { status: "missing" });
  assert.deepEqual(await verifyInstall("  ", { env: env(hosted), roots: noRoots }), { status: "missing" });
  assert.deepEqual(await verifyInstall("not a jws", { env: env(hosted), roots: noRoots }), {
    status: "invalid",
    reason: "malformed",
  });
  // An Xcode-signed one on the hosted project: refused.
  const xcode = appTransaction({});
  assert.deepEqual(await verifyInstall(xcode, { env: env(hosted), roots: noRoots }), {
    status: "invalid",
    reason: "xcode",
  });
  // One that claims to come from the App Store but isn't signed by Apple: refused.
  const forged = appTransaction({ receiptType: "Production", appAppleId: 6822716008 });
  const verdict = await verifyInstall(forged, { env: env({ ...hosted, APPLE_APP_ID: "6822716008" }), roots: noRoots });
  assert.equal(verdict.status, "invalid");
  const sandbox = await verifyInstall(appTransaction({ receiptType: "Sandbox" }), { env: env(hosted), roots: noRoots });
  assert.equal(sandbox.status, "invalid", "an unsigned Sandbox one too");
});

Deno.test("local development: Xcode StoreKit testing works with the flag", async () => {
  const options = { env: env({ ...local, GLOWLIT_ALLOW_XCODE_APP_TRANSACTIONS: "true" }), roots: noRoots };
  assert.deepEqual(await verifyInstall(appTransaction({}), options), {
    status: "verified",
    appTransactionId: "704289572311155034",
    environment: "Xcode",
  });
  const noId = await verifyInstall(appTransaction({ appTransactionId: undefined }), options);
  assert.deepEqual(noId, { status: "verified", appTransactionId: undefined, environment: "Xcode" });
  const otherApp = await verifyInstall(appTransaction({ bundleId: "com.example.other" }), options);
  assert.equal(otherApp.status, "invalid", "the bundle id must be ours");
});

// MARK: - App Store Server Notifications V2

/** An unsigned JWS: only a LocalTesting verifier (which skips signatures) accepts one. */
const unsigned = (payload: unknown) => `${base64url({ alg: "ES256", x5c: [] })}.${base64url(payload)}.c2lnbmF0dXJl`;

function notification(data: Record<string, unknown>, fields: Record<string, unknown> = {}): string {
  return unsigned({
    notificationType: "REFUND",
    notificationUUID: "002e14d5-51f5-4503-b5a8-c3a1af68eb20",
    version: "2.0",
    signedDate: Date.now(),
    data: { environment: "Sandbox", bundleId: "app.glowlit.ios", ...data },
    ...fields,
  });
}

function transaction(fields: Record<string, unknown>): string {
  return unsigned({
    transactionId: "2000000000000002",
    originalTransactionId: "2000000000000001",
    bundleId: "app.glowlit.ios",
    productId: "app.glowlit.pro.yearly",
    expiresDate: Date.now() + 86_400_000,
    revocationDate: Date.now(),
    environment: "LocalTesting",
    ...fields,
  });
}

async function rejection(promise: Promise<unknown>): Promise<NotificationRejected> {
  try {
    await promise;
  } catch (error) {
    assert.ok(error instanceof NotificationRejected, `a NotificationRejected, not ${error}`);
    return error;
  }
  throw new Error("expected a rejection");
}

Deno.test("notifications: malformed, unsigned and forged payloads are refused for good", async () => {
  const options = { env: env({ ...hosted, APPLE_APP_ID: "6822716008" }), roots: noRoots };
  for (const payload of [undefined, 42, "", "not a jws", `${"a".repeat(300_000)}.b.c`]) {
    const refused = await rejection(verifyNotification(payload, options));
    assert.equal(refused.retryable, false, `${String(payload).slice(0, 20)} is refused, not retried`);
  }
  const sandbox = await rejection(verifyNotification(notification({}), options));
  assert.equal(sandbox.retryable, false, "an unsigned Sandbox notification");
  const production = await rejection(
    verifyNotification(notification({ environment: "Production", appAppleId: 6822716008 }), options),
  );
  assert.equal(production.retryable, false, "an unsigned Production notification");
});

Deno.test("notifications: our missing configuration or Apple's roots mean try again later", async () => {
  const noAppId = await rejection(
    verifyNotification(notification({ environment: "Production" }), { env: env(hosted), roots: noRoots }),
  );
  assert.equal(noAppId.retryable, true, "without APPLE_APP_ID, Production waits for Apple's retry");
  const unreachable = () => Promise.reject(new Error("apple.com unreachable"));
  const rootsDown = await rejection(verifyNotification(notification({}), { env: env(hosted), roots: unreachable }));
  assert.equal(rootsDown.retryable, true, "Apple's roots couldn't be loaded");
});

Deno.test("notifications: the transaction inside is decoded by the same verifier, for this app only", async () => {
  // LocalTesting skips Apple's signature (the library's own tests cover the
  // chain); the bundle id and environment checks still apply.
  const local = { verifiers: [new SignedDataVerifier([], false, Environment.LOCAL_TESTING, "app.glowlit.ios")] };
  const data = { environment: "LocalTesting", signedTransactionInfo: transaction({}) };
  const verified = await verifyNotification(notification(data), local);
  assert.equal(verified.notification.notificationType, "REFUND");
  assert.equal(verified.transaction?.originalTransactionId, "2000000000000001");
  assert.equal(verified.transaction?.productId, "app.glowlit.pro.yearly");

  const test = await verifyNotification(
    notification({ environment: "LocalTesting" }, { notificationType: "TEST" }),
    local,
  );
  assert.equal(test.transaction, undefined, "a TEST notification names no transaction");

  const otherApp = await rejection(
    verifyNotification(notification({ ...data, bundleId: "com.example.other" }), local),
  );
  assert.equal(otherApp.retryable, false, "another app's notification");
  const otherTransaction = await rejection(
    verifyNotification(
      notification({ ...data, signedTransactionInfo: transaction({ bundleId: "com.example.other" }) }),
      local,
    ),
  );
  assert.equal(otherTransaction.retryable, false, "another app's transaction inside ours");
  const sandboxInside = await rejection(
    verifyNotification(
      notification({ ...data, signedTransactionInfo: transaction({ environment: "Sandbox" }) }),
      local,
    ),
  );
  assert.equal(sandboxInside.retryable, false, "a transaction from another environment");
});
