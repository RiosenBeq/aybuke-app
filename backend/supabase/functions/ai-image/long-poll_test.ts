// deno test ai-image/
// The long poll with a fake clock and a stubbed job: a finished job answers at
// once, a running one as soon as it finishes or when the wait runs out, and
// wait=0 is the old immediate poll.
import assert from "node:assert/strict";
import { type Clock, holdWhilePending, MAX_WAIT_SECONDS, RECHECK_MS, waitSeconds } from "./long-poll.ts";

/** Time moves only when the poll sleeps. */
function fakeClock() {
  let now = 0;
  const sleeps: number[] = [];
  const clock: Clock = {
    now: () => now,
    sleep: (ms) => {
      sleeps.push(ms);
      now += ms;
      return Promise.resolve();
    },
  };
  return { clock, sleeps, elapsed: () => now };
}

/** A job row that is processing until `finishesAt` (ms on the fake clock), then completed. */
function stubJob(clock: Clock, finishesAt = Infinity) {
  let reads = 0;
  const read = () => {
    reads += 1;
    return Promise.resolve({ id: "job-1", status: clock.now() >= finishesAt ? "completed" : "processing" });
  };
  return { read, reads: () => reads };
}

Deno.test("a finished job is answered at once, with one read and no wait", async () => {
  const time = fakeClock();
  const job = stubJob(time.clock, 0);
  const answer = await holdWhilePending(job.read, MAX_WAIT_SECONDS, { clock: time.clock });
  assert.equal(answer.status, "completed");
  assert.equal(job.reads(), 1);
  assert.deepEqual(time.sleeps, []);
});

Deno.test("a job that finishes mid-wait is answered as soon as it does", async () => {
  const time = fakeClock();
  const job = stubJob(time.clock, 5_500);
  const answer = await holdWhilePending(job.read, MAX_WAIT_SECONDS, { clock: time.clock });
  assert.equal(answer.status, "completed");
  // Read at 0, 1, … 5 s (processing), then at 6 s (completed): no longer than a recheck late.
  assert.equal(time.elapsed(), 6_000);
  assert.equal(job.reads(), 7);
  assert.ok(time.sleeps.every((ms) => ms === RECHECK_MS));
});

Deno.test("wait=0 is the immediate poll: one read, the job as it is", async () => {
  const time = fakeClock();
  const job = stubJob(time.clock);
  const answer = await holdWhilePending(job.read, waitSeconds("0"), { clock: time.clock });
  assert.equal(answer.status, "processing");
  assert.equal(job.reads(), 1);
  assert.deepEqual(time.sleeps, []);
});

Deno.test("a job still running when the wait runs out comes back as it is, never later", async () => {
  const time = fakeClock();
  const job = stubJob(time.clock);
  const answer = await holdWhilePending(job.read, MAX_WAIT_SECONDS, { clock: time.clock });
  assert.equal(answer.status, "processing");
  assert.equal(time.elapsed(), MAX_WAIT_SECONDS * 1_000);
  assert.equal(job.reads(), MAX_WAIT_SECONDS + 1);

  // A wait that isn't a whole number of rechecks ends exactly on time too.
  const short = fakeClock();
  await holdWhilePending(stubJob(short.clock).read, 2.5, { clock: short.clock });
  assert.equal(short.elapsed(), 2_500);
  assert.deepEqual(short.sleeps, [1_000, 1_000, 500]);
});

Deno.test("the wait stops when the app hangs up", async () => {
  const time = fakeClock();
  const hangUp = new AbortController();
  let reads = 0;
  const read = () => {
    reads += 1;
    if (reads === 3) hangUp.abort();
    return Promise.resolve({ status: "processing" });
  };
  const answer = await holdWhilePending(read, MAX_WAIT_SECONDS, { clock: time.clock, signal: hangUp.signal });
  assert.equal(answer.status, "processing");
  assert.equal(reads, 3);
  assert.equal(time.elapsed(), 2_000);
});

Deno.test("a read that fails during the wait ends it with the last good answer", async () => {
  const time = fakeClock();
  let reads = 0;
  const read = () => {
    reads += 1;
    return reads === 3 ? Promise.reject(new Error("connection reset")) : Promise.resolve({ status: "queued" });
  };
  const warn = console.warn;
  console.warn = () => {};
  try {
    assert.equal((await holdWhilePending(read, MAX_WAIT_SECONDS, { clock: time.clock })).status, "queued");
  } finally {
    console.warn = warn;
  }
  assert.equal(reads, 3);
  // The first read's errors still reach the caller (a job that doesn't exist is a 404).
  await assert.rejects(() => holdWhilePending(() => Promise.reject(new Error("not found")), 20, { clock: time.clock }));
});

Deno.test("?wait= is seconds clamped to 0–20, and the full wait when missing or unreadable", () => {
  assert.equal(waitSeconds(null), 20);
  assert.equal(waitSeconds(""), 20);
  assert.equal(waitSeconds("abc"), 20);
  assert.equal(waitSeconds("0"), 0);
  assert.equal(waitSeconds("5"), 5);
  assert.equal(waitSeconds("2.5"), 2.5);
  assert.equal(waitSeconds("45"), 20);
  assert.equal(waitSeconds("-3"), 0);
});
