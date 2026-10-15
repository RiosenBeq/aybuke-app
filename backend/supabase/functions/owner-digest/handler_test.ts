// deno test owner-digest/
// The digest's secret check, its skip without a Resend key and the mail it sends,
// with the summaries and Resend stubbed.
import assert from "node:assert/strict";
import type { RenderedMail } from "../_shared/owner-mail.ts";
import { type DigestDeps, handleDigest, yesterday } from "./handler.ts";

const NOW = new Date(Date.UTC(2026, 9, 15, 6, 0));
const SECRET = "digest-secret-for-tests-0123456789";

function deps(keys: Record<string, string>) {
  const sent: RenderedMail[] = [];
  const days: string[] = [];
  const value: DigestDeps = {
    env: { get: (name) => keys[name] },
    members: () =>
      Promise.resolve({
        members: { total: 321, new_today: 2, new_7_days: 30 },
        pro: { active_members: 8, yearly: 6, monthly: 2 },
        credit_packs: { packs_sold: 4 },
      }),
    daily: (day) => {
      days.push(day);
      return Promise.resolve({
        jobs: { total: 57, completed: 50, failed: 7 },
        failures_by_code: { content_blocked: 5, timeout: 2 },
        estimated_cost_usd: { billed: 1.5 },
        breakers: { all_jobs: 57, all_jobs_cap: 8000, switches: {} },
        top_installs: [{ install: "abcdef123456", jobs: 9 }],
      });
    },
    send: (mail) => {
      sent.push(mail);
      return Promise.resolve({ sent: true });
    },
    now: () => NOW,
  };
  return { value, sent, days };
}

const call = (headers: Record<string, string> = {}, body = "") =>
  new Request("https://example.supabase.co/functions/v1/owner-digest", { method: "POST", headers, body });

Deno.test("without DIGEST_SECRET every call is refused", async () => {
  const { value, sent } = deps({ RESEND_API_KEY: "re_test" });
  assert.equal((await handleDigest(call({ "x-digest-secret": "" }), value)).status, 503);
  assert.equal(sent.length, 0);
});

Deno.test("a wrong or missing secret is refused before anything is read", async () => {
  const { value, sent, days } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  assert.equal((await handleDigest(call(), value)).status, 403);
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET.slice(0, -1) + "x" }), value)).status, 403);
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET + "x" }), value)).status, 403);
  assert.equal(
    (await handleDigest(new Request("https://x.test", { headers: { "x-digest-secret": SECRET } }), value)).status,
    405,
  );
  assert.equal(sent.length + days.length, 0);
});

Deno.test("without RESEND_API_KEY the digest is skipped with a 200", async () => {
  const { value, sent, days } = deps({ DIGEST_SECRET: SECRET });
  const response = await handleDigest(call({ "x-digest-secret": SECRET }), value);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, sent: false, reason: "no_key" });
  assert.equal(sent.length + days.length, 0);
});

Deno.test("the digest covers yesterday (UTC) and leaves out hashed install keys", async () => {
  const { value, sent, days } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  const response = await handleDigest(call({ "x-digest-secret": SECRET }), value);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, sent: true, day: "2026-10-14" });
  assert.deepEqual(days, ["2026-10-14"]);
  assert.equal(sent[0].subject, "Aybuke daily · 2026-10-14 · 57 AI jobs · 8 Pro");
  for (const value of ["321", "content_blocked", "1.50", "57 / 8,000"]) assert.ok(sent[0].text.includes(value), value);
  assert.ok(!sent[0].html.includes("abcdef123456") && !sent[0].text.includes("abcdef123456"));
});

Deno.test("a day can be asked for; anything else falls back to yesterday", async () => {
  const { value, days } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  await handleDigest(call({ "x-digest-secret": SECRET }, JSON.stringify({ day: "2026-10-01" })), value);
  await handleDigest(call({ "x-digest-secret": SECRET }, JSON.stringify({ day: "'; drop table x" })), value);
  assert.deepEqual(days, ["2026-10-01", "2026-10-14"]);
  assert.equal(yesterday(new Date(Date.UTC(2026, 0, 1, 0, 30))), "2025-12-31");
});

Deno.test("a summary or Resend failure fails the call, so the workflow shows it", async () => {
  const broken = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  broken.value.daily = () => Promise.reject(new Error("db down"));
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), broken.value)).status, 500);
  const refused = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  refused.value.send = () => Promise.resolve({ sent: false, reason: "failed" });
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), refused.value)).status, 502);
});

Deno.test("the digest shows xAI's estimated balance, and dashes when it can't be read", async () => {
  const { value, sent } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  value.budget = () =>
    Promise.resolve({
      provider: "xai",
      balance_cents: 1000,
      as_of: "2026-10-15T08:00:00+00:00",
      spent_cents: 804,
      remaining_cents: 196,
      low_alert_sent_at: "2026-10-15T09:00:00+00:00",
    });
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), value)).status, 200);
  for (const line of ["XAI BALANCE (ESTIMATE, NOW)", "Recorded balance: $10.00 on 2026-10-15", "Left: $1.96"]) {
    assert.ok(sent[0].text.includes(line), line);
  }
  assert.ok(sent[0].text.includes("Low-balance mail sent: Yes"));

  const unknown = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  unknown.value.budget = () => Promise.reject(new Error("db down"));
  const warn = console.warn;
  console.warn = () => {};
  try {
    assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), unknown.value)).status, 200);
  } finally {
    console.warn = warn;
  }
  assert.ok(unknown.sent[0].text.includes("Left: –"));
});
