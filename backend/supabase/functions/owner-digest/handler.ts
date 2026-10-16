// The owner's daily digest mail: members, Pro, packs (ops_members_summary),
// yesterday's AI jobs, cost, breakers and safety (ops_daily_summary), the
// image provider's estimated balance (ops_provider_budget) and the RevenueCat
// customers of deleted accounts still waiting for deletion
// (ops_revenuecat_pending, 20261029000002), and yesterday's polls
// (ops_polls_summary, 20261102000000). With REVENUECAT_SECRET_KEY set the
// digest first works through that queue itself; without it, the mail lists the
// App User IDs to delete by hand in the RevenueCat dashboard and the line that
// marks them done (ops_mark_revenuecat_deleted()).
//
//   POST /owner-digest  x-digest-secret: <DIGEST_SECRET>   [{ "day": "2026-10-14" }]
//     → 200 { ok, sent }     sent false with reason "no_key" when RESEND_API_KEY isn't set
//     → 403 wrong or missing secret, 503 DIGEST_SECRET not set (fails closed)
//     → 500 the summaries couldn't be read, 502 Resend refused the mail
//
// The GitHub workflow .github/workflows/owner-digest.yml calls it at 06:00 UTC.
// Counts only: no emails, tokens, prompts or hashed install keys, and no user
// ids except those waiting RevenueCat App User IDs (random ids of accounts
// already deleted, which the privacy policy promises to delete at RevenueCat too).
import { json } from "../_shared/http.ts";
import { count, summaryStats, totalsSection } from "../_shared/owner-alerts.ts";
import { budgetSection } from "../_shared/provider-alerts.ts";
import type { ProcessResult } from "../_shared/revenuecat.ts";
import {
  type Env,
  formatWhen,
  type MailSection,
  ownerAlertsEnabled,
  type OwnerMail,
  type RenderedMail,
  renderOwnerMail,
  secretsMatch,
  type SendResult,
} from "../_shared/owner-mail.ts";

export interface DigestDeps {
  env: Env;
  /** public.ops_members_summary() */
  members(): Promise<unknown>;
  /** public.ops_daily_summary(day) */
  daily(day: string): Promise<unknown>;
  /** public.ops_provider_budget(): optional, the digest goes out without it. */
  budget?(): Promise<unknown>;
  /** public.ops_revenuecat_pending(): optional, the digest goes out without it. */
  revenueCat?(): Promise<unknown>;
  /** public.ops_polls_summary(day): optional, the digest goes out without it. */
  polls?(day: string): Promise<unknown>;
  /** Works through the RevenueCat deletion queue; only given while REVENUECAT_SECRET_KEY is set. */
  deleteRevenueCat?(): Promise<ProcessResult>;
  /** How long the digest waits for deleteRevenueCat (default REVENUECAT_WAIT_MS). */
  revenueCatWaitMs?: number;
  send(mail: RenderedMail): Promise<SendResult>;
  now?: () => Date;
}

const DAY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const UUID_PATTERN = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;
/** The digest doesn't wait longer than this for RevenueCat; what isn't done stays queued for tomorrow. */
export const REVENUECAT_WAIT_MS = 30_000;

/** The UTC day before `now`, as yyyy-MM-dd. */
export function yesterday(now: Date): string {
  return new Date(now.getTime() - 86_400_000).toISOString().slice(0, 10);
}

function failure(status: number, code: string): Response {
  return json({ ok: false, error: { code } }, status);
}

function record(source: unknown, key: string): Record<string, unknown> {
  const value = source && typeof source === "object" ? (source as Record<string, unknown>)[key] : undefined;
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

/** Numbers joined for one row, grouped for reading ("57 / 8,000", "3 · 1"); a dash for a missing one. */
function joined(separator: string, ...values: (number | undefined)[]): string {
  return values.map((value) => value === undefined ? "–" : value.toLocaleString("en-US")).join(separator);
}

function capRow(label: string, used: number | undefined, cap: number | undefined) {
  return { label, value: joined(" / ", used, cap) };
}

/**
 * The RevenueCat customers of deleted accounts still waiting, with what to do
 * about them. `run` is the automatic pass made just before, when the key is set.
 */
export function revenueCatSection(pending: unknown, run?: ProcessResult): MailSection {
  const waiting = count(pending, "count");
  const { app_user_ids: listed, oldest } = (pending && typeof pending === "object" ? pending : {}) as {
    app_user_ids?: unknown;
    oldest?: unknown;
  };
  const ids = (Array.isArray(listed) ? listed : [])
    .filter((id): id is string => typeof id === "string" && UUID_PATTERN.test(id));
  const rows: MailSection["rows"] = [{ label: "Waiting", value: waiting }];
  if (run) {
    rows.push({ label: "Deleted automatically now · failed", value: joined(" · ", run.deleted, run.failed) });
  }
  if (waiting && waiting > 0) {
    rows.push({ label: "Waiting since", value: typeof oldest === "string" ? oldest.slice(0, 10) : undefined });
    rows.push(...ids.map((id) => ({ label: "App User ID", value: id })));
    if (waiting > ids.length) {
      rows.push({
        label: `And ${(waiting - ids.length).toLocaleString("en-US")} more`,
        value: "select upper(user_id::text) from public.pending_revenuecat_deletions order by created_at;",
      });
    }
    rows.push({
      label: "What to do",
      value: "Delete each customer in RevenueCat › Project Glowlit › Customers (search the App User ID), " +
        "then run the line below in the Supabase SQL editor",
    });
    if (ids.length > 0) {
      rows.push({
        label: "Then run",
        value: `select public.ops_mark_revenuecat_deleted(array[${ids.map((id) => `'${id}'`).join(", ")}]);`,
      });
    }
  }
  return { title: "RevenueCat deletions (deleted accounts)", rows };
}

/**
 * Yesterday's "Which vibe?" polls: counts only (no poll ids, questions or
 * pictures). Open reports point at ops_poll_reports(), where a reported poll
 * can be reviewed until its 24 hours end.
 */
export function pollsSection(polls: unknown): MailSection {
  const n = (key: string) => count(polls, key);
  const rows: MailSection["rows"] = [
    capRow("Polls made vs cap", n("created"), n("polls_cap")),
    {
      label: "Blocked: question · picture · unreadable",
      value: joined(" · ", n("blocked_question"), n("blocked_image"), n("invalid_image")),
    },
    { label: "Check couldn't run (given back)", value: n("unavailable") },
    { label: "Votes", value: n("votes") },
    { label: "Reports · taken down", value: joined(" · ", n("reports"), n("takedowns")) },
    capRow("Picture loads vs cap", n("image_loads"), n("image_loads_cap")),
    { label: "Picture egress (MB, to browsers)", value: n("image_mb")?.toFixed(1) },
    { label: "Live now · taken down now", value: joined(" · ", n("live_now"), n("taken_down_now")) },
    { label: "Open reports", value: n("reports_open") },
  ];
  if ((n("reports_open") ?? 0) > 0) {
    rows.push({ label: "Review", value: "select * from public.ops_poll_reports(7);" });
  }
  return { title: "Which vibe? polls", rows };
}

export function digestMail(
  day: string,
  members: unknown,
  daily: unknown,
  at: Date,
  budget?: unknown,
  revenueCat?: unknown,
  revenueCatRun?: ProcessResult,
  polls?: unknown,
): OwnerMail {
  const jobs = record(daily, "jobs");
  const failures = Object.entries(record(daily, "failures_by_code"))
    .map(([code, n]) => ({ code, n: count({ n }, "n") ?? 0 }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 5);
  const breakers = record(daily, "breakers");
  const paused = Object.keys(record(breakers, "switches"));
  const safety = (key: string) => count(daily, "safety", key);
  const reports = (key: string) => count(daily, "reports", key);
  const member = (...path: string[]) => count(members, ...path);
  const sections: MailSection[] = [
    {
      title: `AI jobs on ${day} (UTC)`,
      rows: [
        { label: "Jobs", value: count(jobs, "total") },
        {
          label: "Completed · failed · cancelled",
          value: joined(" · ", count(jobs, "completed"), count(jobs, "failed"), count(jobs, "cancelled")),
        },
        {
          label: "Free · paid · retries",
          value: joined(" · ", count(jobs, "free"), count(jobs, "paid"), count(jobs, "retries")),
        },
        { label: "Members who used AI", value: count(jobs, "users") },
        { label: "Estimated provider cost (USD)", value: count(daily, "estimated_cost_usd", "billed")?.toFixed(2) },
        ...failures.map(({ code, n }) => ({ label: `Failed: ${code}`, value: n })),
      ],
    },
    {
      title: "Breakers and safety",
      rows: [
        capRow("All jobs vs cap", count(breakers, "all_jobs"), count(breakers, "all_jobs_cap")),
        capRow("Free jobs vs cap", count(breakers, "free_jobs"), count(breakers, "free_jobs_cap")),
        capRow("Unverified jobs vs cap", count(breakers, "unverified_jobs"), count(breakers, "unverified_jobs_cap")),
        { label: "AI paused", value: paused.length > 0 ? paused.join(", ") : "No" },
        { label: "Strikes", value: safety("strikes") },
        {
          label: "Cool-downs started · active",
          value: joined(" · ", safety("cooldowns_started"), safety("cooldowns_active")),
        },
        { label: "Blocks new · active", value: joined(" · ", safety("blocks_new"), safety("blocks_active")) },
        { label: "Reports new · open", value: joined(" · ", reports("new"), reports("open")) },
      ],
    },
    budgetSection(budget),
    revenueCatSection(revenueCat, revenueCatRun),
    pollsSection(polls),
    {
      title: "Members",
      rows: [
        {
          label: "New in 7 days · 30 days",
          value: joined(" · ", member("members", "new_7_days"), member("members", "new_30_days")),
        },
        { label: "Active in 7 days", value: member("members", "active_7_days") },
        { label: "Signed in with Apple", value: member("members", "signed_in_with_apple") },
        {
          label: "Pro ever · refunded or revoked",
          value: joined(" · ", member("pro", "ever_subscribed"), member("pro", "revoked_or_refunded")),
        },
        {
          label: "Pack buyers · packs in 30 days",
          value: joined(" · ", member("credit_packs", "buyers"), member("credit_packs", "last_30_days")),
        },
        { label: "Rewarded ads granted", value: member("ad_rewards", "granted") },
      ],
    },
    totalsSection(members),
  ];
  const when = formatWhen(at);
  const [total, pro, jobCount] = [member("members", "total"), member("pro", "active_members"), count(jobs, "total")];
  return {
    subject: `Aybuke daily · ${day} · ${joined("", jobCount)} AI jobs · ${joined("", pro)} Pro`,
    preheader: `${joined("", total)} members, ${joined("", pro)} active Pro, ${joined("", jobCount)} AI jobs on ${day}`,
    eyebrow: "Daily digest",
    headline: `Your day at Aybuke: ${day}`,
    badge: `Sent ${when.utc} · ${when.istanbul}`,
    stats: summaryStats(members),
    sections,
  };
}

export async function handleDigest(req: Request, deps: DigestDeps): Promise<Response> {
  if (req.method !== "POST") return failure(405, "method_not_allowed");
  const expected = deps.env.get("DIGEST_SECRET")?.trim() ?? "";
  if (!expected) {
    console.error("owner-digest: DIGEST_SECRET isn't set, so every call is refused");
    return failure(503, "not_configured");
  }
  if (!secretsMatch(req.headers.get("x-digest-secret"), expected)) return failure(403, "forbidden");

  if (!ownerAlertsEnabled(deps.env)) {
    console.log("owner digest skipped: RESEND_API_KEY isn't set");
    return json({ ok: true, sent: false, reason: "no_key" });
  }

  const now = deps.now?.() ?? new Date();
  const body = await req.json().catch(() => ({})) as { day?: unknown };
  const day = typeof body.day === "string" && DAY_PATTERN.test(body.day) ? body.day : yesterday(now);

  // The balance is an extra: without it the digest shows dashes there.
  const budget = deps.budget?.().catch((error) => {
    console.warn("owner-digest: provider budget unavailable", error instanceof Error ? error.message : error);
    return undefined;
  });
  // RevenueCat too: the automatic pass (key set) first, then what is still waiting.
  const revenueCat = revenueCatQueue(deps);
  // And the polls: dashes when they can't be read.
  const polls = deps.polls?.(day).catch((error) => {
    console.warn("owner-digest: poll summary unavailable", error instanceof Error ? error.message : error);
    return undefined;
  });
  let members: unknown;
  let daily: unknown;
  try {
    [members, daily] = await Promise.all([deps.members(), deps.daily(day)]);
  } catch (error) {
    console.error("owner-digest: summaries unavailable", error instanceof Error ? error.message : error);
    return failure(500, "summary_unavailable");
  }

  const { pending, run } = await revenueCat;
  const result = await deps.send(
    renderOwnerMail(digestMail(day, members, daily, now, await budget, pending, run, await polls)),
  );
  if (!result.sent) return failure(502, result.reason);
  return json({ ok: true, sent: true, day });
}

/** The automatic pass (only with the key), at most REVENUECAT_WAIT_MS, then the queue. Never throws. */
async function revenueCatQueue(deps: DigestDeps): Promise<{ pending?: unknown; run?: ProcessResult }> {
  let run: ProcessResult | undefined;
  if (deps.deleteRevenueCat) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const late = new Promise<undefined>((resolve) => {
      timer = setTimeout(() => resolve(undefined), deps.revenueCatWaitMs ?? REVENUECAT_WAIT_MS);
    });
    run = await Promise.race([deps.deleteRevenueCat().catch(() => undefined), late]);
    clearTimeout(timer);
    if (!run) console.warn("owner-digest: RevenueCat deletions didn't finish in time; the rest stay queued");
  }
  const pending = await deps.revenueCat?.().catch((error) => {
    console.warn("owner-digest: RevenueCat queue unavailable", error instanceof Error ? error.message : error);
    return undefined;
  });
  return { pending, run };
}
