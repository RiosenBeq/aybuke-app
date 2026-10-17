// Owner alerts about the image provider's credit (20261028000000_provider_budget.sql):
//
//   * xAI refuses a job because the team's credit or spending limit ran out
//     (xai.ts isBillingError): the job is refunded as always, AI pauses for
//     everyone (pause_ai_for_provider(), the 'all' switch), so later jobs stop
//     at admit_job() before reaching xAI, and the owner gets one mail per pause.
//   * After each billed job, the estimated balance (ops_provider_budget()): one
//     mail when $2 or less is left, until the owner records a new balance.
//
// Both run after the job's state is stored and never fail it. Like every owner
// mail: amounts, counts and times only, never a user, job or prompt.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { type AlertDeps, count } from "./owner-alerts.ts";
import {
  type DetailRow,
  formatStamp,
  formatWhen,
  type MailAction,
  type MailSection,
  ownerAlertsEnabled,
  type OwnerMail,
  renderOwnerMail,
  runInBackground,
  sendOwnerMail,
  type SendResult,
  type StatCard,
} from "./owner-mail.ts";

type Db = Pick<SupabaseClient, "rpc">;

/** The low-balance mail goes out at or below this estimate. */
export const LOW_BALANCE_CENTS = 200;

/** What ops_provider_budget() returns. */
export interface ProviderBudget {
  provider: string;
  balanceCents: number;
  spentCents: number;
  remainingCents: number;
  /** When the owner last recorded the balance. */
  asOf?: string;
  lowAlertSentAt?: string;
  jobsToday?: number;
}

export function parseBudget(data: unknown): ProviderBudget | undefined {
  if (!data || typeof data !== "object") return undefined;
  const row = data as Record<string, unknown>;
  const [balanceCents, spentCents, remainingCents] = [
    count(row, "balance_cents"),
    count(row, "spent_cents"),
    count(row, "remaining_cents"),
  ];
  if (balanceCents === undefined || spentCents === undefined || remainingCents === undefined) return undefined;
  return {
    provider: typeof row.provider === "string" ? row.provider : "xai",
    balanceCents,
    spentCents,
    remainingCents,
    asOf: typeof row.as_of === "string" ? row.as_of : undefined,
    lowAlertSentAt: typeof row.low_alert_sent_at === "string" ? row.low_alert_sent_at : undefined,
    jobsToday: count(row, "jobs_today"),
  };
}

/** "$1.96"; a negative estimate reads as overspent. */
export function dollars(cents: number): string {
  return `${cents < 0 ? "-" : ""}$${(Math.abs(cents) / 100).toFixed(2)}`;
}

export function providerName(provider: string): string {
  return provider === "xai" ? "xAI" : provider;
}

const call = (db: Db, name: string, args: Record<string, unknown>) =>
  db.rpc(name, args).abortSignal(AbortSignal.timeout(5_000));

/** ops_provider_budget(), or undefined when it can't be read (logged, never thrown). */
export async function readBudget(db: Db, provider = "xai"): Promise<ProviderBudget | undefined> {
  try {
    const { data, error } = await call(db, "ops_provider_budget", { p_provider: provider });
    if (error) console.warn("provider budget unavailable", error.message);
    return error ? undefined : parseBudget(data);
  } catch (error) {
    console.warn("provider budget unavailable", error instanceof Error ? error.message : error);
    return undefined;
  }
}

/** A function that answers true or false; an error is false. */
async function claimed(db: Db, name: string, args: Record<string, unknown>): Promise<boolean> {
  try {
    const { data, error } = await call(db, name, args);
    if (error) console.error(`${name} failed`, error.message);
    return !error && data === true;
  } catch (error) {
    console.error(`${name} failed`, error instanceof Error ? error.message : error);
    return false;
  }
}

/** Where the owner tops up and sees the spending limit. */
export const XAI_CONSOLE_URL = "https://console.x.ai";

function consoleAction(provider: string): MailAction[] {
  return provider === "xai" ? [{ label: "Open the xAI Console", url: XAI_CONSOLE_URL }] : [];
}

function budgetStats(budget: ProviderBudget): StatCard[] {
  return [
    {
      label: "Left (estimate)",
      value: dollars(budget.remainingCents),
      note: `of ${dollars(budget.balanceCents)} recorded`,
      tone: budget.remainingCents <= LOW_BALANCE_CENTS ? "warn" : undefined,
    },
    { label: "AI jobs today (UTC)", value: budget.jobsToday },
    { label: "Spent since recorded", value: dollars(budget.spentCents), note: "billed jobs, estimated" },
    {
      label: "Recorded balance",
      value: dollars(budget.balanceCents),
      note: budget.asOf ? `on ${budget.asOf.slice(0, 10)}` : undefined,
    },
  ];
}

function recordRow(provider: string): DetailRow {
  return {
    label: "Then record the new balance",
    value: `select public.ops_set_provider_balance('${provider}', <new cents>);`,
    kind: "code",
  };
}

export function billingPauseMail(provider: string, budget: ProviderBudget | undefined, at: Date): OwnerMail {
  const name = providerName(provider);
  const when = formatWhen(at);
  return {
    subject: `AI paused · ${name} out of credit`,
    preheader: `${name} refused a job for billing, so AI jobs are paused until you resume them.`,
    eyebrow: "AI paused",
    headline: `${name} is out of credit, so AI is paused`,
    summary: `${name} refused a job for billing. The job was refunded, and every AI job waits until you resume.`,
    tone: "alert",
    stamp: formatStamp(at),
    badge: "Free on-device tools keep working.",
    stats: budget ? budgetStats(budget) : [],
    sections: [
      {
        title: "What happened",
        rows: [
          { label: "Refused by", value: `${name}: out of credit or over the spending limit`, kind: "note" },
          { label: "Paused", value: "Every AI job, until you resume it", kind: "note", tone: "warn" },
          { label: "Time", value: when.utc },
          { label: "Time in Istanbul", value: when.istanbul },
        ],
      },
      {
        title: "What to do",
        steps: true,
        rows: [
          { label: "Top up", value: "console.x.ai › Billing: credits or the spending limit", kind: "note" },
          { label: "Then resume AI", value: "select public.ops_resume_ai();", kind: "code" },
          recordRow(provider),
        ],
      },
    ],
    actions: consoleAction(provider),
    reason: `You get this once per pause: when ${name} refuses a job for billing, the backend pauses AI by itself ` +
      "and mails you.",
  };
}

export function lowBalanceMail(budget: ProviderBudget, at: Date): OwnerMail {
  const name = providerName(budget.provider);
  const left = dollars(Math.max(0, budget.remainingCents));
  const when = formatWhen(at);
  const recorded = `${dollars(budget.balanceCents)} on ${budget.asOf?.slice(0, 10) ?? "–"}`;
  return {
    subject: `${name} balance low · about ${left} left`,
    preheader: `About ${left} of ${name} credit is left (estimate), ${budget.jobsToday ?? "–"} AI jobs today.`,
    eyebrow: "Provider balance",
    headline: `About ${left} left at ${name}`,
    summary: `An estimate: billed jobs cost ${dollars(budget.spentCents)} since you recorded ${recorded}. ` +
      `AI pauses by itself if ${name} runs out.`,
    tone: "info",
    stamp: formatStamp(at),
    attention: [`Top up at ${name}, then record the new balance`],
    stats: budgetStats(budget),
    sections: [
      {
        title: "The estimate",
        rows: [
          { label: "Recorded balance", value: recorded },
          { label: "Billed jobs since then", value: dollars(budget.spentCents) },
          { label: "Left", value: dollars(budget.remainingCents), tone: "warn" },
          { label: "Time", value: when.utc },
        ],
      },
      {
        title: "Top up",
        steps: true,
        rows: [
          { label: "Add credit", value: "console.x.ai › Billing", kind: "note" },
          recordRow(budget.provider),
        ],
      },
    ],
    actions: consoleAction(budget.provider),
    reason: `You get this once when the estimated ${name} balance reaches ${
      dollars(LOW_BALANCE_CENTS)
    } or less, and again only after you record a new balance.`,
  };
}

/** The daily digest's lines about the balance: dashes when it can't be read. */
export function budgetSection(data: unknown): MailSection {
  const budget = parseBudget(data);
  const name = providerName(budget?.provider ?? "xai");
  return {
    title: `${name} balance (estimate, now)`,
    rows: [
      {
        label: "Recorded balance",
        value: budget && `${dollars(budget.balanceCents)} on ${budget.asOf?.slice(0, 10) ?? "–"}`,
      },
      { label: "Billed jobs since then", value: budget && dollars(budget.spentCents) },
      {
        label: "Left",
        value: budget && dollars(budget.remainingCents),
        tone: budget && budget.remainingCents <= LOW_BALANCE_CENTS ? "warn" : undefined,
      },
      { label: "Low-balance mail sent", value: budget && Boolean(budget.lowAlertSentAt) },
    ],
  };
}

/**
 * The provider refused a job for billing: pause AI for everyone and, the first
 * time, mail the owner. True when this call turned the pause on. Never throws.
 */
export async function pauseForProviderBilling(db: Db, deps: AlertDeps = {}, provider = "xai"): Promise<boolean> {
  if (!(await claimed(db, "pause_ai_for_provider", { p_note: "provider_billing" }))) return false;
  console.warn(`AI paused: ${providerName(provider)} refused a job for billing`);
  if (ownerAlertsEnabled(deps.env)) {
    const at = deps.now?.() ?? new Date();
    const mail = readBudget(db, provider).then((budget) =>
      sendOwnerMail(renderOwnerMail(billingPauseMail(provider, budget, at)), deps)
    );
    (deps.background ?? runInBackground)(mail);
  }
  return true;
}

/**
 * After a billed job: one mail once the estimate is LOW_BALANCE_CENTS or less,
 * until the owner records a new balance. Without a Resend key nothing is read
 * or claimed, so the mail still goes out once a key is set. Never throws.
 */
export async function checkProviderBudget(
  db: Db,
  deps: AlertDeps = {},
  provider = "xai",
): Promise<SendResult | undefined> {
  if (!ownerAlertsEnabled(deps.env)) return undefined;
  const budget = await readBudget(db, provider);
  if (!budget || budget.lowAlertSentAt || budget.remainingCents > LOW_BALANCE_CENTS) return undefined;
  if (!(await claimed(db, "claim_provider_low_alert", { p_provider: provider }))) return undefined;
  return await sendOwnerMail(renderOwnerMail(lowBalanceMail(budget, deps.now?.() ?? new Date())), deps);
}
