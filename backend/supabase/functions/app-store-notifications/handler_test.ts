// deno test app-store-notifications/
// The routing and the HTTP contract, with a stubbed verifier and database:
// Apple's signature is checked by _shared/apple.ts (apple_test.ts), and what
// each action does to entitlements and credits by
// backend/supabase/tests/app_store_notifications_test.sql.
import assert from "node:assert/strict";
import { NotificationRejected, verifyNotification } from "../_shared/apple.ts";
import { handleNotification, type NotificationDeps, type NotificationRecord, routeNotification } from "./handler.ts";

const PERIOD_END = Date.UTC(2026, 10, 14, 12);
const SIGNED = Date.UTC(2026, 9, 14, 9, 30);

interface Fake {
  type?: string;
  uuid?: string;
  productId?: string;
  transaction?: boolean;
  /** Apple's signedDate; null leaves it out. */
  signedDate?: number | null;
}

/** A verifier that accepts one fake notification per payload name, as Apple's library would decode it. */
function stubVerifier(fakes: Record<string, Fake>): NotificationDeps["verify"] {
  return (payload) => {
    const fake = typeof payload === "string" ? fakes[payload] : undefined;
    if (!fake) return Promise.reject(new NotificationRejected("INVALID_CERTIFICATE", false));
    return Promise.resolve({
      notification: {
        notificationType: fake.type,
        notificationUUID: fake.uuid ?? crypto.randomUUID(),
        data: { environment: "Production", bundleId: "app.glowlit.ios" },
        signedDate: fake.signedDate === null ? undefined : fake.signedDate ?? SIGNED,
      },
      transaction: fake.transaction === false ? undefined : {
        transactionId: "tx-latest",
        originalTransactionId: "otx-first",
        productId: fake.productId ?? "app.glowlit.pro.monthly",
        expiresDate: PERIOD_END,
      },
    });
  };
}

/** A database that, like record_app_store_notification, applies each UUID once. */
function stubDatabase() {
  const seen = new Set<string>();
  const applied: NotificationRecord[] = [];
  const record = (row: NotificationRecord) => {
    if (seen.has(row.p_notification_uuid)) return Promise.resolve("duplicate");
    seen.add(row.p_notification_uuid);
    if (row.p_action === "none") return Promise.resolve("ignored");
    applied.push(row);
    return Promise.resolve("applied");
  };
  return { record, applied };
}

const post = (body: unknown) =>
  new Request("https://example.supabase.co/functions/v1/app-store-notifications", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

async function send(fake: Fake, db = stubDatabase()) {
  const response = await handleNotification(
    post({ signedPayload: "signed" }),
    { verify: stubVerifier({ signed: fake }), record: db.record },
  );
  return { status: response.status, body: await response.json(), applied: db.applied };
}

Deno.test("routing: refunds and revocations of Pro, refunds of packs, nothing else", () => {
  const pro = { productId: "app.glowlit.pro.yearly", transactionId: "t", originalTransactionId: "o" };
  const pack = { productId: "app.glowlit.credits.30", transactionId: "t", originalTransactionId: "t" };
  assert.equal(routeNotification("REFUND", pro), "revoke");
  assert.equal(routeNotification("REVOKE", pro), "revoke");
  assert.equal(routeNotification("REFUND_REVERSED", pro), "restore");
  assert.equal(routeNotification("REFUND", pack), "refund_pack");
  assert.equal(routeNotification("REFUND", { ...pack, productId: "app.glowlit.credits.100" }), "refund_pack");
  assert.equal(routeNotification("REFUND_REVERSED", pack), "restore_pack");
  for (
    const type of ["DID_RENEW", "EXPIRED", "REFUND_DECLINED", "CONSUMPTION_REQUEST", "TEST", "SOMETHING_NEW", undefined]
  ) {
    assert.equal(routeNotification(type, pro), "none", `${type} on Pro`);
    assert.equal(routeNotification(type, pack), "none", `${type} on a pack`);
  }
  assert.equal(routeNotification("REVOKE", pack), "none", "packs aren't shared with family");
  assert.equal(routeNotification("REFUND", undefined), "none", "no transaction");
  assert.equal(routeNotification("REFUND", { ...pro, productId: "com.example.other" }), "none", "not our product");
  assert.equal(routeNotification("REFUND", { ...pro, productId: "toString" }), "none", "no prototype lookups");
  assert.equal(routeNotification("REFUND", { ...pro, originalTransactionId: undefined }), "none");
  assert.equal(routeNotification("REFUND", { ...pack, transactionId: undefined }), "none");
});

Deno.test("a Pro refund revokes the subscription for the refunded period", async () => {
  const { status, body, applied } = await send({ type: "REFUND", uuid: "9a0f1c8e-0000-4000-8000-000000000001" });
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true, outcome: "applied" });
  assert.deepEqual(applied, [{
    p_notification_uuid: "9a0f1c8e-0000-4000-8000-000000000001",
    p_notification_type: "REFUND",
    p_subtype: null,
    p_environment: "Production",
    p_action: "revoke",
    p_transaction_id: "tx-latest",
    p_original_transaction_id: "otx-first",
    p_product_id: "app.glowlit.pro.monthly",
    p_period_end: new Date(PERIOD_END).toISOString(),
    p_signed_at: new Date(SIGNED).toISOString(),
  }]);
});

Deno.test("Apple's signedDate goes to the database, which orders a refund and its reversal by it", async () => {
  const reversed = await send({ type: "REFUND_REVERSED", signedDate: SIGNED + 1000 });
  assert.equal(reversed.applied[0].p_signed_at, new Date(SIGNED + 1000).toISOString());
  // Without one, or with one no date can hold, the order of arrival decides (null), never a 500.
  for (const signedDate of [null, 8.64e15 + 1]) {
    const { status, applied } = await send({ type: "REFUND", signedDate });
    assert.equal(status, 200, String(signedDate));
    assert.equal(applied[0].p_signed_at, null, String(signedDate));
  }
});

Deno.test("a stale notification (out of order) is answered 200, so Apple stops sending it", async () => {
  const response = await handleNotification(post({ signedPayload: "signed" }), {
    verify: stubVerifier({ signed: { type: "REFUND" } }),
    record: () => Promise.resolve("stale"),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, outcome: "stale" });
});

Deno.test("a Family Sharing revocation revokes, a reversed refund restores", async () => {
  const revoke = await send({ type: "REVOKE" });
  assert.equal(revoke.status, 200);
  assert.equal(revoke.applied[0].p_action, "revoke");
  const reversed = await send({ type: "REFUND_REVERSED" });
  assert.equal(reversed.status, 200);
  assert.equal(reversed.applied[0].p_action, "restore");
});

Deno.test("a credit pack refund takes the pack back by its transaction id", async () => {
  const { status, applied } = await send({ type: "REFUND", productId: "app.glowlit.credits.100" });
  assert.equal(status, 200);
  assert.equal(applied[0].p_action, "refund_pack");
  assert.equal(applied[0].p_transaction_id, "tx-latest");
  assert.equal(applied[0].p_product_id, "app.glowlit.credits.100");
});

Deno.test("any other type is recorded and answered 200, so Apple never retries it", async () => {
  for (const type of ["DID_RENEW", "CONSUMPTION_REQUEST", "A_TYPE_APPLE_ADDS_NEXT_YEAR"]) {
    const { status, body, applied } = await send({ type });
    assert.equal(status, 200, type);
    assert.deepEqual(body, { ok: true, outcome: "ignored" });
    assert.equal(applied.length, 0, `${type} changes nothing`);
  }
  const test = await send({ type: "TEST", transaction: false });
  assert.equal(test.status, 200);
  assert.equal(test.body.outcome, "ignored");
});

Deno.test("a replayed notification UUID changes nothing the second time", async () => {
  const db = stubDatabase();
  const fake = { type: "REFUND", uuid: "9a0f1c8e-0000-4000-8000-000000000002" };
  const first = await send(fake, db);
  const again = await send(fake, db);
  assert.equal(first.body.outcome, "applied");
  assert.equal(again.status, 200, "a repeat is still answered 200");
  assert.equal(again.body.outcome, "duplicate");
  assert.equal(db.applied.length, 1);
});

Deno.test("a bad or forged payload is a 400 and records nothing", async () => {
  const db = stubDatabase();
  let calls = 0;
  const record = (row: NotificationRecord) => {
    calls++;
    return db.record(row);
  };
  // The real verifier, with no trusted roots: nothing unsigned gets through.
  const hosted = new Map([["SUPABASE_URL", "https://efapupjvidyqhqdevmcu.supabase.co"], [
    "APPLE_APP_ID",
    "6822716008",
  ]]);
  const verify: NotificationDeps["verify"] = (payload) =>
    verifyNotification(payload, { env: { get: (name) => hosted.get(name) }, roots: () => Promise.resolve([]) });
  const base64url = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const reversal = {
    notificationType: "REFUND_REVERSED",
    notificationUUID: "9a0f1c8e-0000-4000-8000-000000000003",
    data: { environment: "Production", bundleId: "app.glowlit.ios", appAppleId: 6822716008 },
  };
  const forged = [
    "eyJhbGciOiJFUzI1NiJ9",
    // Well formed and claiming to be ours, but not signed by Apple.
    [base64url({ alg: "ES256", x5c: [] }), base64url(reversal), "c2ln"].join("."),
  ];
  for (
    const body of [
      "",
      "not json",
      "null",
      "[]",
      { signed: "x" },
      { signedPayload: 7 },
      ...forged.map((p) => ({ signedPayload: p })),
    ]
  ) {
    const response = await handleNotification(post(body), { verify, record });
    assert.equal(response.status, 400, JSON.stringify(body));
    assert.equal((await response.json()).error.code, "invalid_payload");
  }
  // Signed by Apple, but not a notification we can count: no UUID.
  const noUuid = await handleNotification(post({ signedPayload: "signed" }), {
    verify: () => Promise.resolve({ notification: { notificationType: "REFUND" } }),
    record,
  });
  assert.equal(noUuid.status, 400);
  assert.equal(calls, 0, "nothing was recorded");
});

Deno.test("when it can't be checked or saved now, Apple is asked to retry", async () => {
  const unavailable = await handleNotification(post({ signedPayload: "signed" }), {
    verify: () => Promise.reject(new NotificationRejected("verifier_unavailable", true)),
    record: () => Promise.reject(new Error("must not be called")),
  });
  assert.equal(unavailable.status, 503);
  const notSaved = await handleNotification(post({ signedPayload: "signed" }), {
    verify: stubVerifier({ signed: { type: "REFUND" } }),
    record: () => Promise.reject(new Error("connection reset")),
  });
  assert.equal(notSaved.status, 500);
});

Deno.test("only POST", async () => {
  const response = await handleNotification(
    new Request("https://example.supabase.co/functions/v1/app-store-notifications"),
    { verify: stubVerifier({}), record: stubDatabase().record },
  );
  assert.equal(response.status, 405);
});
