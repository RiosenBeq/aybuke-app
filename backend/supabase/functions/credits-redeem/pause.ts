// Whether cloud AI takes jobs right now, for everyone, as admit_job() decides
// it (migrations 20261022 and 20261025000001): the owner's switches
// (ops_pause_ai(), and the 'all' pause pause_ai_for_provider() turns on when
// the image provider refuses a job for billing) and the day's hard breakers
// in credit_policy(). An 'all' pause stops every job; a free one stops jobs
// paid with free daily credits, where ad credits land too, while Pro credits
// and packs still work. The app hides "Watch a short ad" while either is on and
// says so on the paywall and the packs, so nobody earns or buys credits she
// can't use today (GET /credits-redeem, AppCore `AIServicePause`).

export interface AIPause {
  ai_paused: boolean;
  /** Only free daily credits rest: Pro credits and packs still work. */
  free_only?: boolean;
  /** Seconds until the pause ends at the latest (the owner can end it sooner). */
  retry_after?: number;
}

type RpcCall = () => PromiseLike<{ data: unknown; error: { message: string } | null }>;

interface Breakers {
  all_jobs?: unknown;
  all_jobs_cap?: unknown;
  free_jobs?: unknown;
  free_jobs_cap?: unknown;
  switches?: Record<string, unknown> | null;
}

function nextUtcDay(now: Date): number {
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
}

/**
 * From ops_daily_summary()'s breakers for today. Null when the reply isn't
 * one: unknown, never "paused" or "not paused".
 */
export function pauseFromSummary(summary: unknown, now: Date): AIPause | null {
  const breakers = (summary as { breakers?: Breakers } | null | undefined)?.breakers;
  if (!breakers || typeof breakers !== "object") return null;
  const at = now.getTime();
  const switchedUntil = (scope: string): number | null => {
    const value = breakers.switches?.[scope];
    const time = typeof value === "string" ? Date.parse(value) : NaN;
    return Number.isFinite(time) && time > at ? time : null;
  };
  // admit_job() stops at the cap itself (count >= cap), until the next UTC day.
  const capReached = (count: unknown, cap: unknown): number | null =>
    typeof count === "number" && typeof cap === "number" && count >= cap ? nextUtcDay(now) : null;
  const latest = (...times: (number | null)[]): number | null => {
    const known = times.filter((time): time is number => time !== null);
    return known.length ? Math.max(...known) : null;
  };
  const paused = (until: number, freeOnly: boolean): AIPause => ({
    ai_paused: true,
    free_only: freeOnly,
    retry_after: Math.max(1, Math.ceil((until - at) / 1000)),
  });

  const all = latest(switchedUntil("all"), capReached(breakers.all_jobs, breakers.all_jobs_cap));
  if (all !== null) return paused(all, false);
  const free = latest(switchedUntil("free"), capReached(breakers.free_jobs, breakers.free_jobs_cap));
  if (free !== null) return paused(free, true);
  return { ai_paused: false };
}

/**
 * Reads the pause through `call` (ops_daily_summary(), service role only),
 * at most once every `ttlMs` per instance: the answer is the same for
 * everyone, so a busy paywall can't turn into a busy database. A failed or
 * odd read is unknown (null) and isn't kept.
 */
export function pauseReader(call: RpcCall, ttlMs = 30_000): (now?: Date) => Promise<AIPause | null> {
  let cached: { readAt: number; summary: unknown } | null = null;
  return async (now = new Date()) => {
    if (!cached || now.getTime() - cached.readAt >= ttlMs || now.getTime() < cached.readAt) {
      const { data, error } = await call();
      if (error) {
        console.error("ops_daily_summary failed", error.message);
        return null;
      }
      if (pauseFromSummary(data, now) === null) return null;
      cached = { readAt: now.getTime(), summary: data };
    }
    return pauseFromSummary(cached.summary, now);
  };
}
