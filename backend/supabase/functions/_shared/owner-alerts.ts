// Owner alerts for purchases: a mail when a Pro subscription is stored for the
// first time, or a credit pack is granted for the first time (owner-mail.ts
// sends it). They run after the database work committed, in the background,
// and never delay or fail the request that caused them.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import {
  formatWhen,
  type MailSection,
  ownerAlertsEnabled,
  type OwnerMail,
  renderOwnerMail,
  runInBackground,
  sendOwnerMail,
  type SendResult,
  type StatCard,
} from "./owner-mail.ts";
import type { MailDeps } from "./owner-mail.ts";

type Db = Pick<SupabaseClient, "from" | "rpc">;

export interface AlertDeps extends MailDeps {
  /** Where the alert task goes (default: runInBackground). Tests collect it to await it. */
  background?: (task: Promise<unknown>) => void;
  now?: () => Date;
  /** Checked in the background before sending: the alert is dropped when it answers false. */
  onlyIf?: () => Promise<boolean>;
}

/** A first purchase, described without anything that identifies the buyer. */
export type Purchase =
  | { kind: "pro"; productId: string; environment: string; trial: boolean }
  | { kind: "pack"; productId: string; environment: string; credits: number };

// The looks of public.ops_members_summary() (20261026000000_ops_members.sql).
type Json = Record<string, unknown>;

function section(source: unknown, key: string): Json {
  const value = source && typeof source === "object" ? (source as Json)[key] : undefined;
  return value && typeof value === "object" ? value as Json : {};
}

/** A number from the summary, or undefined (shown as a dash) when it isn't one. */
export function count(source: unknown, ...path: string[]): number | undefined {
  let value: unknown = source;
  for (const key of path) value = value && typeof value === "object" ? (value as Json)[key] : undefined;
  const number = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof number === "number" && Number.isFinite(number) ? number : undefined;
}

export function planName(productId: string): string {
  if (productId.includes("yearly")) return "Yearly";
  if (productId.includes("monthly")) return "Monthly";
  const pack = /credits\.(\d+)$/.exec(productId);
  return pack ? `${pack[1]} credits` : "Other";
}

export function isSandbox(environment: string): boolean {
  return environment.toLowerCase() !== "production";
}

/** The four headline numbers. */
export function summaryStats(summary: unknown): StatCard[] {
  return [
    { label: "Members", value: count(summary, "members", "total") },
    { label: "New today (UTC)", value: count(summary, "members", "new_today") },
    { label: "Active Pro", value: count(summary, "pro", "active_members") },
    { label: "Packs sold", value: count(summary, "credit_packs", "packs_sold") },
  ];
}

export function totalsSection(summary: unknown): MailSection {
  const pro = section(summary, "pro");
  return {
    title: "Totals",
    rows: [
      { label: "Pro yearly · monthly", value: `${count(pro, "yearly") ?? "–"} · ${count(pro, "monthly") ?? "–"}` },
      { label: "Credits sold in packs", value: count(summary, "credit_packs", "credits_sold") },
      { label: "AI jobs (last 7 days)", value: count(summary, "ai_jobs", "last_7_days") },
      { label: "AI jobs (all time)", value: count(summary, "ai_jobs", "total") },
    ],
  };
}

export function purchaseMail(purchase: Purchase, summary: unknown, at: Date): OwnerMail {
  const sandbox = isSandbox(purchase.environment);
  const plan = planName(purchase.productId);
  const when = formatWhen(at);
  const isPro = purchase.kind === "pro";
  const what = isPro ? `Pro ${plan}` : `Credit pack · ${plan}`;
  const environment = sandbox ? "Sandbox (test, no money)" : "Production";
  const rows = [
    { label: "Plan", value: what },
    ...(isPro ? [{ label: "Free trial", value: purchase.trial }] : [{ label: "Credits", value: purchase.credits }]),
    { label: "Environment", value: environment },
    { label: "Time", value: when.utc },
    { label: "Time in Istanbul", value: when.istanbul },
  ];
  const subject = `${sandbox ? "[TEST] " : ""}${isPro ? "New Pro member" : "Credit pack sold"} · ${plan}`;
  return {
    subject,
    preheader: `${what} · ${environment} · ${when.utc}`,
    eyebrow: isPro ? "New Pro member" : "Credit pack sold",
    headline: isPro ? `Someone just went Pro ${plan}` : `Someone just bought ${plan}`,
    badge: sandbox ? "Sandbox purchase: a test, no money changed hands" : undefined,
    stats: summaryStats(summary),
    sections: [{ title: "This purchase", rows }, totalsSection(summary)],
  };
}

/** ops_members_summary(), or undefined when it can't be read in time (the mail shows dashes). */
async function membersSummary(db: Db): Promise<unknown> {
  try {
    const { data, error } = await db.rpc("ops_members_summary").abortSignal(AbortSignal.timeout(5_000));
    if (error) console.warn("owner alert: summary unavailable", error.message);
    return error ? undefined : data;
  } catch (error) {
    console.warn("owner alert: summary unavailable", error instanceof Error ? error.message : error);
    return undefined;
  }
}

/** Builds and sends one purchase alert. Never throws. */
export async function sendPurchaseAlert(db: Db, purchase: Purchase, deps: AlertDeps = {}): Promise<SendResult> {
  const summary = await membersSummary(db);
  return sendOwnerMail(renderOwnerMail(purchaseMail(purchase, summary, deps.now?.() ?? new Date())), deps);
}

/** Queues a purchase alert after the response; never awaited by the request. */
export function alertPurchase(db: Db, purchase: Purchase, deps: AlertDeps = {}): void {
  const task = (async () => {
    if (deps.onlyIf && !(await deps.onlyIf())) return { sent: false, reason: "skipped" };
    return await sendPurchaseAlert(db, purchase, deps);
  })();
  (deps.background ?? runInBackground)(task);
}

/**
 * Whether a row matching the filter exists. Errors and timeouts count as
 * "exists": an alert is skipped rather than the request delayed or failed.
 */
async function exists(db: Db, table: string, filters: Record<string, string>): Promise<boolean> {
  try {
    let query = db.from(table).select("user_id");
    for (const [column, value] of Object.entries(filters)) query = query.eq(column, value);
    const { data, error } = await query.limit(1).abortSignal(AbortSignal.timeout(2_000));
    return Boolean(error) || (Array.isArray(data) && data.length > 0);
  } catch {
    return true;
  }
}

export function entitlementKnown(db: Db, originalTransactionId: string): Promise<boolean> {
  return exists(db, "entitlements", { original_transaction_id: originalTransactionId });
}

export function packGranted(db: Db, transactionId: string): Promise<boolean> {
  return exists(db, "credit_ledger", { kind: "grant_pack", source_ref: transactionId });
}

export { ownerAlertsEnabled };
