// deno test credits-redeem/
// GET /credits-redeem says whether cloud AI takes jobs, as admit_job() decides
// it from ops_daily_summary()'s breakers: the owner's switches (and the
// provider's billing pause, which is the 'all' switch) and the day's caps.
import assert from "node:assert/strict";
import { pauseFromSummary, pauseReader } from "./pause.ts";

const now = new Date("2026-10-15T20:00:00Z");
const midnight = 4 * 3600; // seconds to the next UTC day

function summary(breakers: Record<string, unknown>) {
  return {
    day: "2026-10-15",
    breakers: {
      all_jobs: 10,
      all_jobs_cap: 400,
      free_jobs: 5,
      free_jobs_cap: 60,
      unverified_jobs: 0,
      unverified_jobs_cap: 10,
      switches: {},
      ...breakers,
    },
  };
}

Deno.test("nothing paused", () => {
  assert.deepEqual(pauseFromSummary(summary({}), now), { ai_paused: false });
});

Deno.test("the owner's or the provider's 'all' switch pauses everything until it ends", () => {
  const pause = pauseFromSummary(summary({ switches: { all: "2026-10-15T21:00:00.123+00:00" } }), now);
  assert.deepEqual(pause, { ai_paused: true, free_only: false, retry_after: 3601 });
});

Deno.test("the day's hard breaker pauses everything until the next UTC day", () => {
  const pause = pauseFromSummary(summary({ all_jobs: 400 }), now);
  assert.deepEqual(pause, { ai_paused: true, free_only: false, retry_after: midnight });
});

Deno.test("the free breaker and the free switch pause free credits only", () => {
  assert.deepEqual(pauseFromSummary(summary({ free_jobs: 60 }), now), {
    ai_paused: true,
    free_only: true,
    retry_after: midnight,
  });
  assert.deepEqual(pauseFromSummary(summary({ switches: { free: "2026-10-15T20:30:00Z" } }), now), {
    ai_paused: true,
    free_only: true,
    retry_after: 1800,
  });
});

Deno.test("an 'all' pause wins over a free one, and the later end counts", () => {
  const both = summary({ free_jobs: 60, switches: { all: "2026-10-15T20:10:00Z", free: "2026-10-16T09:00:00Z" } });
  assert.deepEqual(pauseFromSummary(both, now), { ai_paused: true, free_only: false, retry_after: 600 });
  const longer = summary({ all_jobs: 400, switches: { all: "2026-10-17T00:00:00Z" } });
  assert.equal(pauseFromSummary(longer, now)?.retry_after, 28 * 3600);
});

Deno.test("yesterday's caps end at midnight UTC, even from a cached summary", () => {
  const justAfter = new Date("2026-10-16T00:00:10Z");
  assert.deepEqual(pauseFromSummary(summary({ all_jobs: 400, free_jobs: 60 }), justAfter), { ai_paused: false });
  const switched = summary({ free_jobs: 60, switches: { all: "2026-10-16T01:00:00Z" } });
  assert.deepEqual(pauseFromSummary(switched, justAfter), { ai_paused: true, free_only: false, retry_after: 3590 });
});

Deno.test("an ended switch pauses nothing", () => {
  assert.deepEqual(pauseFromSummary(summary({ switches: { all: "2026-10-15T19:59:59Z" } }), now), {
    ai_paused: false,
  });
});

Deno.test("an odd reply is unknown, never a verdict", () => {
  assert.equal(pauseFromSummary(null, now), null);
  assert.equal(pauseFromSummary({}, now), null);
  assert.equal(pauseFromSummary([], now), null);
  // Counts it can't read aren't a reached cap.
  assert.deepEqual(pauseFromSummary(summary({ all_jobs: "400", switches: null }), now), { ai_paused: false });
});

Deno.test("the reader keeps a good answer briefly and never keeps a failure", async () => {
  let calls = 0;
  let reply: { data: unknown; error: { message: string } | null } = { data: null, error: { message: "timeout" } };
  const read = pauseReader(() => {
    calls++;
    return Promise.resolve(reply);
  }, 30_000);

  assert.equal(await read(now), null);
  reply = { data: summary({ free_jobs: 60 }), error: null };
  assert.equal((await read(now))?.free_only, true);
  assert.equal(calls, 2, "a failure isn't cached");

  // Within the cache: no new read, and the wait counts down from the same answer.
  const later = new Date(now.getTime() + 10_000);
  assert.equal((await read(later))?.retry_after, midnight - 10);
  assert.equal(calls, 2);

  // After it: read again.
  reply = { data: summary({}), error: null };
  assert.deepEqual(await read(new Date(now.getTime() + 30_000)), { ai_paused: false });
  assert.equal(calls, 3);
});
