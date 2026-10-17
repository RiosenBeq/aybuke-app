// deno test owner-digest/
// The digest's secret check, its skip without a Resend key and the mail it sends,
// with the summaries and Resend stubbed.
import assert from "node:assert/strict";
import type { RenderedMail } from "../_shared/owner-mail.ts";
import { type DigestDeps, handleDigest, pollsSection, revenueCatSection, yesterday } from "./handler.ts";

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
  assert.equal(sent[0].subject, "Daily digest · 14 Oct · 57 AI jobs · 8 Pro");
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

const PENDING = {
  count: 3,
  oldest: "2026-10-12T09:30:00+00:00",
  failed: 0,
  app_user_ids: ["0B7C1E2A-1111-4C2B-9D3E-0123456789AB", "5F00D1E2-2222-4A1B-8C2D-ABCDEF012345"],
};

Deno.test("RevenueCat customers waiting are listed with what to do, and the line that marks them done", async () => {
  const { value, sent } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  value.revenueCat = () => Promise.resolve(PENDING);
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), value)).status, 200);
  const text = sent[0].text;
  for (
    const line of [
      "REVENUECAT DELETIONS (DELETED ACCOUNTS)",
      "Waiting: 3",
      "Waiting since: 2026-10-12",
      "App User ID: 0B7C1E2A-1111-4C2B-9D3E-0123456789AB",
      "App User ID: 5F00D1E2-2222-4A1B-8C2D-ABCDEF012345",
      "And 1 more: select upper(user_id::text) from public.pending_revenuecat_deletions order by created_at;",
      "What to do: Delete each customer in RevenueCat › Project Aybuke › Customers",
      "Then run: select public.ops_mark_revenuecat_deleted(array['0B7C1E2A-1111-4C2B-9D3E-0123456789AB', " +
      "'5F00D1E2-2222-4A1B-8C2D-ABCDEF012345']);",
    ]
  ) {
    assert.ok(text.includes(line), line);
  }
  assert.ok(sent[0].html.includes("0B7C1E2A-1111-4C2B-9D3E-0123456789AB"));
  assert.ok(!text.includes("Deleted automatically"), "no automatic pass without the key");
});

Deno.test("nothing waiting is one line; anything but an App User ID is never shown", () => {
  const none = revenueCatSection({ count: 0, oldest: null, app_user_ids: [] });
  assert.deepEqual(none.rows, [{ label: "Waiting", value: 0, tone: undefined }]);

  const odd = revenueCatSection({
    count: 2,
    app_user_ids: ["'); drop table x; --", "<b>0B7C1E2A-1111-4C2B-9D3E-0123456789AB</b>", 42],
  });
  const shown = JSON.stringify(odd.rows);
  assert.ok(!shown.includes("drop table") && !shown.includes("<b>"), shown);
  assert.ok(!odd.rows.some((row) => row.label === "Then run"), "no line without ids to mark");
  assert.ok(odd.rows.some((row) => row.label === "And 2 more"));

  const unknown = revenueCatSection(undefined);
  assert.deepEqual(unknown.rows, [{ label: "Waiting", value: undefined, tone: undefined }]);
});

Deno.test("with the key, the digest deletes first, then reports what is left; it never waits long", async () => {
  const order: string[] = [];
  const { value, sent } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  value.deleteRevenueCat = () => {
    order.push("delete");
    return Promise.resolve({ deleted: 5, failed: 1, waiting: false });
  };
  value.revenueCat = () => {
    order.push("read");
    return Promise.resolve({ ...PENDING, count: 1, app_user_ids: PENDING.app_user_ids.slice(0, 1) });
  };
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), value)).status, 200);
  assert.deepEqual(order, ["delete", "read"]);
  assert.ok(sent[0].text.includes("Deleted automatically now · failed: 5 · 1"));
  assert.ok(sent[0].text.includes("Waiting: 1"));

  // RevenueCat hangs: the digest goes out anyway, the rest stays queued.
  const slow = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  slow.value.deleteRevenueCat = () => new Promise(() => {});
  slow.value.revenueCatWaitMs = 20;
  slow.value.revenueCat = () => Promise.reject(new Error("db down"));
  const warn = console.warn;
  console.warn = () => {};
  try {
    assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), slow.value)).status, 200);
  } finally {
    console.warn = warn;
  }
  assert.ok(slow.sent[0].text.includes("Waiting: –"));
  assert.ok(!slow.sent[0].text.includes("Deleted automatically"));
});

Deno.test("the digest counts yesterday's polls, never their content, and points at open reports", async () => {
  const { value, sent } = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  const days: string[] = [];
  value.polls = (day) => {
    days.push(day);
    return Promise.resolve({
      day,
      created: 12,
      polls_cap: 300,
      unverified_attempts: 4,
      unverified_cap: 30,
      blocked_question: 2,
      blocked_image: 1,
      invalid_image: 0,
      unavailable: 0,
      votes: 87,
      reports: 3,
      takedowns: 1,
      image_loads: 240,
      image_loads_unique: 180,
      image_loads_cap: 2000,
      image_loads_raw_cap: 4000,
      image_bytes: 15_204_352,
      image_mb: 14.5,
      live_now: 9,
      taken_down_now: 1,
      reports_open: 2,
    });
  };
  assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), value)).status, 200);
  assert.deepEqual(days, ["2026-10-14"]);
  for (
    const line of [
      "WHICH VIBE? POLLS",
      "Polls made vs cap: 12 / 300",
      "Attempts without a verified download vs cap: 4 / 30",
      "Blocked: question · picture · unreadable: 2 · 1 · 0",
      "Votes: 87",
      "Reports · taken down: 3 · 1",
      "Picture loads (once per picture and address) vs cap: 180 / 2,000",
      "Picture loads (all) vs backstop: 240 / 4,000",
      "Picture egress (MB, to browsers): 14.5",
      "select * from public.ops_poll_reports(7);",
    ]
  ) assert.ok(sent[0].text.includes(line), line);

  const quiet = pollsSection({ created: 0, reports_open: 0 });
  assert.ok(!quiet.rows.some((row) => row.label === "Review"), "nothing to review, no line");
  assert.equal(pollsSection(undefined).rows[0].value, "– / –", "dashes when the summary is missing");

  const down = deps({ RESEND_API_KEY: "re_test", DIGEST_SECRET: SECRET });
  down.value.polls = () => Promise.reject(new Error("db down"));
  const warn = console.warn;
  console.warn = () => {};
  try {
    assert.equal((await handleDigest(call({ "x-digest-secret": SECRET }), down.value)).status, 200, "still sent");
  } finally {
    console.warn = warn;
  }
});
