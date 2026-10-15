// The long poll: a GET for a job that is still queued or processing waits
// inside the request, reading the job again about once a second, until it
// finishes or the wait runs out, then answers exactly as an immediate poll.
// Every poll is one Edge Function invocation (the free plan has about 500k a
// month), so holding it saves the app most of its polls, and a timer awaited
// inside the request uses no CPU time. The app gives a poll 45 s
// (RequestFactory.pollTimeout) and builds before it 30 s, so the longest wait
// stays at least 10 s below either.

/** The longest a poll is held, in seconds. */
export const MAX_WAIT_SECONDS = 20;
/** How often a held poll reads the job again. */
export const RECHECK_MS = 1_000;

/** `?wait=` in seconds, clamped to 0–20; missing or unreadable is the full wait. */
export function waitSeconds(param: string | null): number {
  const value = param === null || param.trim() === "" ? NaN : Number(param);
  if (!Number.isFinite(value)) return MAX_WAIT_SECONDS;
  return Math.min(MAX_WAIT_SECONDS, Math.max(0, value));
}

export interface Clock {
  now(): number;
  sleep(ms: number): Promise<void>;
}

export const systemClock: Clock = {
  now: () => Date.now(),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

export function isPending(job: { status: string }): boolean {
  return job.status === "queued" || job.status === "processing";
}

/**
 * Reads the job with `read` (which also moves a pending job forward) and,
 * while it's still pending, again about once a second for at most `seconds`
 * or until the app hangs up (`signal`). Returns the last read. A read that
 * fails during the wait ends it with the read before, so a passing database
 * error can't turn a running job into an error; the app simply asks again.
 */
export async function holdWhilePending<Job extends { status: string }>(
  read: () => Promise<Job>,
  seconds: number,
  options: { clock?: Clock; signal?: AbortSignal } = {},
): Promise<Job> {
  const clock = options.clock ?? systemClock;
  const deadline = clock.now() + seconds * 1_000;
  let job = await read();
  for (;;) {
    const left = deadline - clock.now();
    if (!isPending(job) || left <= 0 || options.signal?.aborted) return job;
    await clock.sleep(Math.min(RECHECK_MS, left));
    if (options.signal?.aborted) return job;
    try {
      job = await read();
    } catch (error) {
      console.warn("held poll stopped early:", error instanceof Error ? error.message : error);
      return job;
    }
  }
}
