// deno test _shared/
// Production and Sandbox AppTransactions are signed by Apple, so only the
// rules around them can be tested here (Apple's library has its own tests
// for the signature chain). An Xcode-environment JWS is signed by a local
// certificate the library doesn't check, which is exactly why it's refused
// unless the dev flag is set on a local backend.
import assert from "node:assert/strict";
import { isFreeTrial, ROOT_CERTIFICATE_URLS, verifyInstall, xcodeAllowed } from "./apple.ts";

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
