// deno test _shared/
// Owner alerts: the mail builder, sending through Resend (fetch stubbed), and
// that a purchase mails the owner only the first time the server stores it.
import assert from "node:assert/strict";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import type { JWSTransactionDecodedPayload } from "npm:@apple/app-store-server-library@3.1.0";
import { resolveEntitlement } from "./apple.ts";
import { type AlertDeps, alertPurchase, planName, purchaseMail } from "./owner-alerts.ts";
import {
  DEFAULT_ALERT_FROM,
  DEFAULT_ALERT_TO,
  escapeHtml,
  FOOTER,
  formatDay,
  formatStamp,
  formatWhen,
  renderOwnerMail,
  RESEND_ENDPOINT,
  secretsMatch,
  sendOwnerMail,
} from "./owner-mail.ts";

const SUMMARY = {
  members: { total: 1234, new_today: 7, new_7_days: 40 },
  pro: { active_members: 12, yearly: 9, monthly: 3 },
  credit_packs: { packs_sold: 5, credits_sold: 330 },
  ai_jobs: { total: 900, last_7_days: 210 },
};
const AT = new Date(Date.UTC(2026, 9, 15, 6, 5));

function env(values: Record<string, string>) {
  return { get: (name: string) => values[name] };
}

/** A fetch that records each Resend call and answers 200. */
function stubFetch(status = 200) {
  const calls: { url: string; init: RequestInit; body: Record<string, unknown> }[] = [];
  const fetch = (input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init: init ?? {}, body: JSON.parse(String(init?.body ?? "{}")) });
    return Promise.resolve(new Response(JSON.stringify({ id: "mail" }), { status }));
  };
  return { calls, fetch: fetch as typeof globalThis.fetch };
}

Deno.test("escapeHtml escapes every character that could open markup", () => {
  assert.equal(
    escapeHtml(`<a href="x" onclick='y'>&</a>`),
    "&lt;a href=&quot;x&quot; onclick=&#39;y&#39;&gt;&amp;&lt;/a&gt;",
  );
});

Deno.test("the mail escapes interpolated values and keeps subjects on one line", () => {
  const mail = renderOwnerMail({
    subject: "Hi\r\nBcc: someone@example.com",
    preheader: "<b>pre</b>",
    eyebrow: "<script>alert(1)</script>",
    headline: "Tom & <Jerry>",
    summary: "<i>sum</i>",
    stamp: "<s>now</s>",
    badge: `"quoted"`,
    attention: ["<u>look</u>"],
    stats: [{ label: "<img src=x>", value: "<svg>", note: "<em>n</em>" }],
    sections: [{
      title: "<h1>",
      rows: [{ label: "a<b", value: "c>d" }, { label: "<q>", value: "<code>", kind: "code" }, {
        label: "<p>",
        value: "<pre>",
        kind: "note",
      }],
    }],
    actions: [{ label: "<b>go</b>", url: "https://x.test/?a=1&b=<2>" }],
    reason: "<small>why</small>",
  });
  assert.equal(mail.subject, "Hi Bcc: someone@example.com");
  for (
    const raw of [
      "<script>",
      "<img src=x>",
      "<svg>",
      "<Jerry>",
      "<h1>",
      "a<b",
      "c>d",
      "<b>pre</b>",
      "<i>sum</i>",
      "<s>now</s>",
      "<u>look</u>",
      "<em>n</em>",
      "<q>",
      "<code>",
      "<pre>",
      "<b>go</b>",
      "b=<2>",
      "<small>why</small>",
    ]
  ) {
    assert.ok(!mail.html.includes(raw), raw);
  }
  assert.ok(mail.html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"));
  assert.ok(mail.html.includes("Tom &amp; &lt;Jerry&gt;"));
  assert.ok(mail.text.includes("Tom & <Jerry>"), "the plain-text part isn't HTML");
  assert.ok(!mail.text.includes("\r"));
});

Deno.test("the design: 600 px tables, the blush header with a solid fallback, the live wordmark and the footer", () => {
  const { html, text } = renderOwnerMail(purchaseMail(
    { kind: "pro", productId: "app.glowlit.pro.yearly", environment: "Production", trial: true },
    SUMMARY,
    AT,
  ));
  assert.ok(html.includes('width="600"') && html.includes("max-width:600px"));
  assert.ok(html.includes('bgcolor="#F7C1D9"') && html.includes("linear-gradient("));
  assert.ok(html.includes("#F8E0EA") && html.includes("#121212"));
  assert.ok(html.includes('<meta name="color-scheme" content="light dark">'));
  assert.ok(html.includes("@media (prefers-color-scheme:dark)") && html.includes("max-width:480px"));
  assert.match(html, /font-weight:700;[^>]*>aybuke<\/span>/);
  assert.ok(text.startsWith("aybuke · New Pro member\n15 Oct, 06:05 UTC\n"));
  for (const part of [FOOTER, "the first time the backend stores a new Pro subscription"]) {
    assert.ok(html.includes(part) && text.includes(part), part);
  }
  for (
    const value of [
      "1,234",
      "+7 today (UTC)",
      "9 yearly · 3 monthly",
      "Pro Yearly, starting with the free trial · Production · 06:05 UTC",
      "2026-10-15 06:05 UTC",
      "2026-10-15 09:05 Istanbul",
    ]
  ) {
    assert.ok(html.includes(value) && text.includes(value), value);
  }
});

Deno.test("a sandbox purchase is labelled a test; plans come from the product id", () => {
  const mail = purchaseMail(
    { kind: "pro", productId: "app.glowlit.pro.monthly", environment: "Sandbox", trial: false },
    SUMMARY,
    AT,
  );
  assert.equal(mail.subject, "[TEST] New Pro member · Monthly");
  assert.match(mail.badge ?? "", /test/i);
  assert.equal(
    purchaseMail(
      { kind: "pro", productId: "app.glowlit.pro.yearly", environment: "Production", trial: false },
      SUMMARY,
      AT,
    ).badge,
    undefined,
  );
  assert.equal(planName("app.glowlit.credits.100"), "100 credits");
  assert.deepEqual(formatWhen(AT), { utc: "2026-10-15 06:05 UTC", istanbul: "2026-10-15 09:05 Istanbul" });
  assert.equal(formatStamp(AT), "15 Oct, 06:05 UTC");
  assert.deepEqual(formatDay("2026-10-14"), { short: "14 Oct", long: "Wednesday 14 October" });
  assert.deepEqual(formatDay("not a day"), { short: "not a day", long: "not a day" });
});

Deno.test("a missing summary shows dashes instead of failing", () => {
  const { text } = renderOwnerMail(
    purchaseMail(
      { kind: "pack", productId: "app.glowlit.credits.30", environment: "Production", credits: 30 },
      undefined,
      AT,
    ),
  );
  assert.match(text, /Members: –/);
  assert.match(text, /Credits: 30/);
});

Deno.test("without RESEND_API_KEY nothing is sent and nothing throws", async () => {
  const { calls, fetch } = stubFetch();
  const result = await sendOwnerMail(
    renderOwnerMail(
      purchaseMail(
        { kind: "pro", productId: "app.glowlit.pro.yearly", environment: "Production", trial: false },
        SUMMARY,
        AT,
      ),
    ),
    { env: env({}), fetch },
  );
  assert.deepEqual(result, { sent: false, reason: "no_key" });
  assert.equal(calls.length, 0);
});

Deno.test("Resend gets the key, the defaults and both parts; its errors are returned, never thrown", async () => {
  const { calls, fetch } = stubFetch();
  const mail = renderOwnerMail(
    purchaseMail(
      { kind: "pro", productId: "app.glowlit.pro.yearly", environment: "Production", trial: false },
      SUMMARY,
      AT,
    ),
  );
  assert.deepEqual(await sendOwnerMail(mail, { env: env({ RESEND_API_KEY: "re_test" }), fetch }), { sent: true });
  assert.equal(calls[0].url, RESEND_ENDPOINT);
  assert.equal((calls[0].init.headers as Record<string, string>).Authorization, "Bearer re_test");
  assert.deepEqual(calls[0].body.to, [DEFAULT_ALERT_TO]);
  assert.equal(calls[0].body.from, DEFAULT_ALERT_FROM);
  assert.ok(String(calls[0].body.html).startsWith("<!doctype html>") && String(calls[0].body.text).length > 0);

  const custom = stubFetch();
  await sendOwnerMail(mail, {
    env: env({
      RESEND_API_KEY: "re_test",
      OWNER_ALERT_TO: "a@x.test, b@x.test",
      OWNER_ALERT_FROM: "Aybuke <alerts@x.test>",
    }),
    fetch: custom.fetch,
  });
  assert.deepEqual(custom.calls[0].body.to, ["a@x.test", "b@x.test"]);
  assert.equal(custom.calls[0].body.from, "Aybuke <alerts@x.test>");

  const failing = stubFetch(422);
  assert.equal(
    (await sendOwnerMail(mail, { env: env({ RESEND_API_KEY: "re_test" }), fetch: failing.fetch })).sent,
    false,
  );
  const throwing = (() => Promise.reject(new TypeError("network down"))) as typeof globalThis.fetch;
  assert.equal((await sendOwnerMail(mail, { env: env({ RESEND_API_KEY: "re_test" }), fetch: throwing })).sent, false);
});

Deno.test("secretsMatch compares exactly and refuses an empty secret", () => {
  assert.ok(secretsMatch("s3cret-value", "s3cret-value"));
  assert.ok(!secretsMatch("s3cret-valuf", "s3cret-value"));
  assert.ok(!secretsMatch("s3cret", "s3cret-value"));
  assert.ok(!secretsMatch(null, "s3cret-value"));
  assert.ok(!secretsMatch("", ""));
});

// MARK: - Only a new subscription or pack mails the owner

const USER = "8d2f6a10-5c4e-4b7a-9f00-000000000abc";
const ORIGINAL = "2000000999999999";

/** Just enough of supabase-js: entitlements by original_transaction_id, record_entitlement, the summary. */
function fakeDb(known: Set<string>) {
  const rpcs: string[] = [];
  const from = () => {
    const filters: Record<string, string> = {};
    const query = {
      select: () => query,
      eq: (column: string, value: string) => {
        filters[column] = value;
        return query;
      },
      gt: () => query,
      order: () => query,
      limit: () => query,
      abortSignal: () => query,
      then: (resolve: (value: unknown) => void) => {
        const id = filters.original_transaction_id;
        resolve({ data: id && known.has(id) ? [{ user_id: USER }] : [], error: null });
      },
    };
    return query;
  };
  const rpc = (name: string, args: Record<string, unknown> = {}) => {
    rpcs.push(name);
    const data = name === "record_entitlement" ? (known.add(String(args.p_original_transaction_id)), true) : SUMMARY;
    const result = Promise.resolve({ data, error: null });
    return Object.assign(result, { abortSignal: () => result });
  };
  return { db: { from, rpc } as unknown as SupabaseClient, rpcs };
}

const verify = () =>
  Promise.resolve({
    productId: "app.glowlit.pro.yearly",
    originalTransactionId: ORIGINAL,
    transactionId: "2000001000000001",
    expiresDate: Date.now() + 7 * 86_400_000,
    environment: "Sandbox",
    offerDiscountType: "FREE_TRIAL",
  } as unknown as JWSTransactionDecodedPayload);

function alerts(keys: Record<string, string> = { RESEND_API_KEY: "re_test" }) {
  const tasks: Promise<unknown>[] = [];
  const stub = stubFetch();
  const deps: AlertDeps = { env: env(keys), fetch: stub.fetch, background: (task) => tasks.push(task) };
  return { deps, calls: stub.calls, settled: () => Promise.all(tasks) };
}

Deno.test("a subscription stored for the first time mails the owner once, without ids", async () => {
  const { db } = fakeDb(new Set());
  const mail = alerts();
  const status = await resolveEntitlement(db, USER, "jws", { verify, alerts: mail.deps });
  assert.deepEqual(status, { isPro: true, isTrial: true });
  await mail.settled();
  assert.equal(mail.calls.length, 1);
  const body = JSON.stringify(mail.calls[0].body);
  assert.match(String(mail.calls[0].body.subject), /^\[TEST\] New Pro member · Yearly$/);
  for (const secret of [USER, ORIGINAL, "2000001000000001", "jws"]) assert.ok(!body.includes(secret), secret);
});

Deno.test("a subscription the server already knows (renewal, another account) sends nothing", async () => {
  const { db } = fakeDb(new Set([ORIGINAL]));
  const mail = alerts();
  await resolveEntitlement(db, USER, "jws", { verify, alerts: mail.deps });
  await mail.settled();
  assert.equal(mail.calls.length, 0);
});

Deno.test("without RESEND_API_KEY the purchase path doesn't even look", async () => {
  const { db, rpcs } = fakeDb(new Set());
  const mail = alerts({});
  assert.deepEqual(await resolveEntitlement(db, USER, "jws", { verify, alerts: mail.deps }), {
    isPro: true,
    isTrial: true,
  });
  await mail.settled();
  assert.equal(mail.calls.length, 0);
  assert.deepEqual(rpcs, ["record_entitlement"]);
});

Deno.test("a pack alert is dropped when the grant didn't happen", async () => {
  const { db } = fakeDb(new Set());
  const mail = alerts();
  const pack = { kind: "pack" as const, productId: "app.glowlit.credits.30", environment: "Production", credits: 30 };
  alertPurchase(db, pack, { ...mail.deps, onlyIf: () => Promise.resolve(false) });
  alertPurchase(db, pack, { ...mail.deps, onlyIf: () => Promise.resolve(true) });
  await mail.settled();
  assert.equal(mail.calls.length, 1);
  assert.equal(mail.calls[0].body.subject, "Credit pack sold · 30 credits");
});
