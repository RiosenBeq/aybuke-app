// deno test _shared/
// The provider's credit, with the database and Resend stubbed: a billing
// refusal pauses AI and mails the owner once per pause, and the estimated
// balance mails once at $2 or less until a new balance is recorded.
import assert from "node:assert/strict";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import type { AlertDeps } from "./owner-alerts.ts";
import {
  budgetSection,
  checkProviderBudget,
  dollars,
  LOW_BALANCE_CENTS,
  pauseForProviderBilling,
} from "./provider-alerts.ts";

const AT = new Date(Date.UTC(2026, 9, 15, 9, 30));

const budget = (remaining: number, extra: Record<string, unknown> = {}) => ({
  provider: "xai",
  balance_cents: 1000,
  as_of: "2026-10-15T08:00:00+00:00",
  spent_cents: 1000 - remaining,
  remaining_cents: remaining,
  low_alert_sent_at: null,
  jobs_today: 37,
  ...extra,
});

/** pause_ai_for_provider and claim_provider_low_alert answer true once, like the SQL; `fail` makes a function error. */
function fakeDb(options: { budget?: unknown; fail?: string[] } = {}) {
  const rpcs: string[] = [];
  let paused = false;
  let claimed = false;
  const rpc = (name: string) => {
    rpcs.push(name);
    let result: { data: unknown; error: { message: string } | null };
    if (options.fail?.includes(name)) {
      result = { data: null, error: { message: "db down" } };
    } else if (name === "pause_ai_for_provider") {
      result = { data: !paused, error: null };
      paused = true;
    } else if (name === "claim_provider_low_alert") {
      result = { data: !claimed, error: null };
      claimed = true;
    } else if (name === "ops_provider_budget") {
      result = { data: options.budget ?? null, error: null };
    } else {
      result = { data: null, error: { message: `unexpected ${name}` } };
    }
    const promise = Promise.resolve(result);
    return Object.assign(promise, { abortSignal: () => promise });
  };
  return { db: { rpc } as unknown as SupabaseClient, rpcs };
}

/** Resend stubbed; background tasks collected so the test can wait for them. */
function alerts(keys: Record<string, string> = { RESEND_API_KEY: "re_test" }) {
  const tasks: Promise<unknown>[] = [];
  const mails: Record<string, unknown>[] = [];
  const fetch = ((_input: string | URL | Request, init?: RequestInit) => {
    mails.push(JSON.parse(String(init?.body ?? "{}")));
    return Promise.resolve(new Response(JSON.stringify({ id: "mail" }), { status: 200 }));
  }) as typeof globalThis.fetch;
  const deps: AlertDeps = {
    env: { get: (name) => keys[name] },
    fetch,
    now: () => AT,
    background: (t) => tasks.push(t),
  };
  return { deps, mails, settled: () => Promise.all(tasks) };
}

/** Runs `body` with console.warn and console.error silenced. */
async function quietly(body: () => Promise<void>) {
  const { warn, error } = console;
  console.warn = console.error = () => {};
  try {
    await body();
  } finally {
    Object.assign(console, { warn, error });
  }
}

Deno.test("a billing refusal pauses AI once and mails the owner once, with how to resume", async () => {
  await quietly(async () => {
    const { db, rpcs } = fakeDb({ budget: budget(0) });
    const mail = alerts();
    assert.equal(await pauseForProviderBilling(db, mail.deps), true);
    assert.equal(await pauseForProviderBilling(db, mail.deps), false, "already paused");
    await mail.settled();
    assert.equal(rpcs.filter((name) => name === "pause_ai_for_provider").length, 2);
    assert.equal(mail.mails.length, 1);
    assert.equal(mail.mails[0].subject, "Aybuke AI paused: xAI balance");
    const text = String(mail.mails[0].text);
    for (const line of ["console.x.ai", "select public.ops_resume_ai();", "ops_set_provider_balance('xai'"]) {
      assert.ok(text.includes(line), line);
    }
  });
});

Deno.test("without a Resend key AI still pauses, and nothing is read or mailed", async () => {
  await quietly(async () => {
    const { db, rpcs } = fakeDb({ budget: budget(0) });
    const mail = alerts({});
    assert.equal(await pauseForProviderBilling(db, mail.deps), true);
    await mail.settled();
    assert.deepEqual(rpcs, ["pause_ai_for_provider"]);
    assert.equal(mail.mails.length, 0);
  });
});

Deno.test("a pause the database refuses is logged, never thrown, and mails nothing", async () => {
  await quietly(async () => {
    const { db } = fakeDb({ fail: ["pause_ai_for_provider"] });
    const mail = alerts();
    assert.equal(await pauseForProviderBilling(db, mail.deps), false);
    await mail.settled();
    assert.equal(mail.mails.length, 0);
  });
});

Deno.test("the low-balance mail goes out once at $2 or less, with the estimate and how to top up", async () => {
  const { db } = fakeDb({ budget: budget(196) });
  const mail = alerts();
  assert.deepEqual(await checkProviderBudget(db, mail.deps), { sent: true });
  assert.equal(await checkProviderBudget(db, mail.deps), undefined, "claimed already");
  assert.equal(mail.mails.length, 1);
  assert.equal(mail.mails[0].subject, "Aybuke: xAI balance about $1.96 left");
  const text = String(mail.mails[0].text);
  for (
    const line of [
      "AI jobs today (UTC): 37",
      "Recorded balance: $10.00 on 2026-10-15",
      "console.x.ai",
      "select public.ops_set_provider_balance('xai', <new cents>);",
    ]
  ) assert.ok(text.includes(line), line);

  const atTheLine = fakeDb({ budget: budget(LOW_BALANCE_CENTS) });
  assert.deepEqual(await checkProviderBudget(atTheLine.db, alerts().deps), { sent: true });
  // An estimate below zero still reads as a balance in the subject.
  const overspent = alerts();
  await checkProviderBudget(fakeDb({ budget: budget(-40) }).db, overspent.deps);
  assert.equal(overspent.mails[0].subject, "Aybuke: xAI balance about $0.00 left");
});

Deno.test("above $2, already mailed, unreadable or without a key: nothing is claimed or sent", async () => {
  await quietly(async () => {
    const plenty = fakeDb({ budget: budget(LOW_BALANCE_CENTS + 1) });
    const mail = alerts();
    assert.equal(await checkProviderBudget(plenty.db, mail.deps), undefined);
    assert.deepEqual(plenty.rpcs, ["ops_provider_budget"]);

    const mailed = fakeDb({ budget: budget(50, { low_alert_sent_at: "2026-10-15T09:00:00+00:00" }) });
    assert.equal(await checkProviderBudget(mailed.db, mail.deps), undefined);
    assert.deepEqual(mailed.rpcs, ["ops_provider_budget"]);

    const broken = fakeDb({ fail: ["ops_provider_budget"] });
    assert.equal(await checkProviderBudget(broken.db, mail.deps), undefined);
    assert.deepEqual(broken.rpcs, ["ops_provider_budget"]);

    const noKey = fakeDb({ budget: budget(50) });
    assert.equal(await checkProviderBudget(noKey.db, alerts({}).deps), undefined);
    assert.deepEqual(noKey.rpcs, [], "without a key the claim waits for one");
    assert.equal(mail.mails.length, 0);
  });
});

Deno.test("amounts read as dollars, and the digest section shows dashes without a budget", () => {
  assert.equal(dollars(196), "$1.96");
  assert.equal(dollars(1000), "$10.00");
  assert.equal(dollars(-40), "-$0.40");
  const known = budgetSection(budget(196));
  assert.equal(known.title, "xAI balance (estimate, now)");
  assert.deepEqual(known.rows.map((row) => row.value), ["$10.00 on 2026-10-15", "$8.04", "$1.96", false]);
  assert.ok(budgetSection(undefined).rows.every((row) => row.value === undefined));
});
