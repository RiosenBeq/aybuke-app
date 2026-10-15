// Owner alerts by email, sent with Resend (https://resend.com/docs/api-reference/emails/send-email).
//
//   RESEND_API_KEY    required; without it every alert is skipped (one log line, never an error)
//   OWNER_ALERT_TO    default hello@buaze.com (comma-separated for more than one)
//   OWNER_ALERT_FROM  default "Aybuke <onboarding@resend.dev>", which only delivers to the
//                     Resend account's own address until a domain is verified there
//
// The mails carry counts, plans and times only: never a user id, email, token,
// transaction id or prompt. Everything interpolated is escaped.

export interface Env {
  get(name: string): string | undefined;
}

export const RESEND_ENDPOINT = "https://api.resend.com/emails";
export const DEFAULT_ALERT_TO = "hello@buaze.com";
export const DEFAULT_ALERT_FROM = "Aybuke <onboarding@resend.dev>";

const BLUSH = "#F7C1D9";
const PETAL = "#F8E0EA";
const PEACH = "#FFD9C7";
const INK = "#121212";
const MUTED = "#6E5A64";
const WHITE = "#FFFFFF";
const SANS = "Poppins,-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif";
const SERIF = "'New York',Georgia,'Times New Roman',serif";

export type Value = string | number | boolean | null | undefined;

export interface StatCard {
  label: string;
  value: Value;
}

export interface DetailRow {
  label: string;
  value: Value;
}

export interface MailSection {
  title: string;
  rows: DetailRow[];
}

/** What an owner mail says. Only these fields reach the mail. */
export interface OwnerMail {
  subject: string;
  /** The preview line inboxes show next to the subject. */
  preheader: string;
  /** Small capitals above the headline, e.g. "New Pro member". */
  eyebrow: string;
  headline: string;
  /** A highlighted note under the headline, e.g. that a purchase was a sandbox test. */
  badge?: string;
  stats: StatCard[];
  sections: MailSection[];
}

export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

const FOOTER = "Owner alert from your Aybuke backend";

export function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** One line, no control characters: subjects and plain-text values can't add headers or lines. */
function oneLine(value: unknown): string {
  // deno-lint-ignore no-control-regex
  return String(value ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
}

/** Numbers grouped for reading (12,345); anything else as one line; nothing as a dash. */
export function formatValue(value: Value): string {
  if (typeof value === "number") return Number.isFinite(value) ? value.toLocaleString("en-US") : "–";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  const text = oneLine(value);
  return text || "–";
}

/** "2026-10-15 06:00" in a time zone. */
function clock(date: Date, timeZone: string): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(date).map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`;
}

/** The same moment in UTC and in Istanbul. */
export function formatWhen(date: Date): { utc: string; istanbul: string } {
  return { utc: `${clock(date, "UTC")} UTC`, istanbul: `${clock(date, "Europe/Istanbul")} Istanbul` };
}

function statCell(stat: StatCard): string {
  return `<td class="gl-cell" width="50%" valign="top" style="padding:6px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="gl-card" bgcolor="${WHITE}" style="background-color:${WHITE};border:1px solid ${BLUSH};border-radius:18px;">
<tr><td style="padding:18px 20px;">
<div class="gl-ink" style="font-family:${SANS};font-size:32px;line-height:38px;font-weight:700;color:${INK};">${
    escapeHtml(formatValue(stat.value))
  }</div>
<div class="gl-muted" style="font-family:${SANS};font-size:12px;line-height:16px;letter-spacing:1px;text-transform:uppercase;color:${MUTED};padding-top:4px;">${
    escapeHtml(stat.label)
  }</div>
</td></tr>
</table>
</td>`;
}

function statGrid(stats: StatCard[]): string {
  if (stats.length === 0) return "";
  const rows: string[] = [];
  for (let i = 0; i < stats.length; i += 2) {
    const pair = stats.slice(i, i + 2);
    rows.push(`<tr>${pair.map(statCell).join("")}${pair.length === 1 ? '<td width="50%"></td>' : ""}</tr>`);
  }
  return `<tr><td class="gl-body" bgcolor="${PETAL}" style="background-color:${PETAL};padding:18px 26px 6px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${rows.join("")}</table>
</td></tr>`;
}

function sectionBlock(section: MailSection): string {
  const rows = section.rows.map((row) =>
    `<tr>
<td class="gl-muted" style="font-family:${SANS};font-size:14px;line-height:20px;color:${MUTED};padding:9px 0;border-bottom:1px solid ${PETAL};">${
      escapeHtml(row.label)
    }</td>
<td class="gl-ink" align="right" style="font-family:${SANS};font-size:14px;line-height:20px;font-weight:600;color:${INK};padding:9px 0 9px 12px;border-bottom:1px solid ${PETAL};">${
      escapeHtml(formatValue(row.value))
    }</td>
</tr>`
  ).join("");
  return `<tr><td class="gl-body" bgcolor="${PETAL}" style="background-color:${PETAL};padding:12px 32px 4px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="gl-card" bgcolor="${WHITE}" style="background-color:${WHITE};border-radius:18px;">
<tr><td style="padding:16px 20px 8px;">
<div class="gl-ink" style="font-family:${SANS};font-size:13px;line-height:18px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:${INK};padding-bottom:4px;">${
    escapeHtml(section.title)
  }</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${rows}</table>
</td></tr>
</table>
</td></tr>`;
}

/** Table layout, inline styles, 600 px: what Gmail, Outlook and Apple Mail all render. */
function renderHtml(mail: OwnerMail): string {
  const badge = mail.badge
    ? `<div style="padding-top:14px;"><span class="gl-badge" style="display:inline-block;font-family:${SANS};font-size:13px;line-height:18px;font-weight:600;color:${INK};background-color:${WHITE};border:1px solid ${INK};border-radius:999px;padding:5px 12px;">${
      escapeHtml(mail.badge)
    }</span></div>`
    : "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${escapeHtml(oneLine(mail.subject))}</title>
<style>
@media (prefers-color-scheme: dark) {
  .gl-page, .gl-body { background-color: #1E1418 !important; }
  .gl-card, .gl-badge { background-color: #2A1D23 !important; border-color: #4A3640 !important; }
  .gl-ink { color: #FBEFF4 !important; }
  .gl-muted { color: #D9BCC9 !important; }
}
@media only screen and (max-width: 480px) {
  .gl-cell { display: block !important; width: 100% !important; }
}
</style>
</head>
<body class="gl-page" style="margin:0;padding:0;background-color:${PETAL};" bgcolor="${PETAL}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">${escapeHtml(mail.preheader)}</div>
<table role="presentation" class="gl-page" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${PETAL}" style="background-color:${PETAL};">
<tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;">
<tr><td bgcolor="${BLUSH}" style="background-color:${BLUSH};background-image:linear-gradient(135deg,${BLUSH} 0%,#FBD0DC 55%,${PEACH} 100%);border-radius:24px 24px 0 0;padding:30px 32px 28px;">
<div style="font-family:${SERIF};font-style:italic;font-size:30px;line-height:36px;color:${INK};">Aybuke</div>
<div style="font-family:${SANS};font-size:12px;line-height:16px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:${INK};padding-top:18px;">${
    escapeHtml(mail.eyebrow)
  }</div>
<div style="font-family:${SANS};font-size:24px;line-height:32px;font-weight:700;color:${INK};padding-top:6px;">${
    escapeHtml(mail.headline)
  }</div>
${badge}
</td></tr>
${statGrid(mail.stats)}
${mail.sections.map(sectionBlock).join("\n")}
<tr><td class="gl-body" bgcolor="${PETAL}" style="background-color:${PETAL};border-radius:0 0 24px 24px;padding:18px 32px 28px;">
<div class="gl-muted" style="font-family:${SANS};font-size:12px;line-height:18px;color:${MUTED};text-align:center;">${FOOTER}</div>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}

function renderText(mail: OwnerMail): string {
  const lines = [`AYBUKE · ${oneLine(mail.eyebrow).toUpperCase()}`, oneLine(mail.headline)];
  if (mail.badge) lines.push(`[${oneLine(mail.badge)}]`);
  if (mail.stats.length > 0) {
    lines.push("");
    for (const stat of mail.stats) lines.push(`${oneLine(stat.label)}: ${formatValue(stat.value)}`);
  }
  for (const section of mail.sections) {
    lines.push("", oneLine(section.title).toUpperCase());
    for (const row of section.rows) lines.push(`  ${oneLine(row.label)}: ${formatValue(row.value)}`);
  }
  lines.push("", "--", FOOTER);
  return lines.join("\n");
}

export function renderOwnerMail(mail: OwnerMail): RenderedMail {
  return { subject: oneLine(mail.subject).slice(0, 200), html: renderHtml(mail), text: renderText(mail) };
}

// MARK: - Sending

export type SendResult =
  | { sent: true }
  | { sent: false; reason: "no_key" | "failed"; detail?: string };

export interface MailDeps {
  env?: Env;
  fetch?: typeof fetch;
  /** Gives up on Resend after this long (default 8 s). */
  timeoutMs?: number;
}

export function ownerAlertsEnabled(env: Env = Deno.env): boolean {
  return Boolean(env.get("RESEND_API_KEY")?.trim());
}

function recipients(env: Env): string[] {
  const list = (env.get("OWNER_ALERT_TO") ?? "").split(",").map((to) => to.trim()).filter(Boolean);
  return list.length > 0 ? list : [DEFAULT_ALERT_TO];
}

/**
 * Sends one owner mail. Never throws: a missing key skips with one log line,
 * and a Resend error or timeout is logged and returned.
 */
export async function sendOwnerMail(
  mail: RenderedMail,
  deps: MailDeps = {},
  idempotencyKey?: string,
): Promise<SendResult> {
  const env = deps.env ?? Deno.env;
  const key = env.get("RESEND_API_KEY")?.trim();
  if (!key) {
    console.log("owner alert skipped: RESEND_API_KEY isn't set");
    return { sent: false, reason: "no_key" };
  }
  const headers: Record<string, string> = { Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  try {
    const response = await (deps.fetch ?? fetch)(RESEND_ENDPOINT, {
      method: "POST",
      headers,
      body: JSON.stringify({
        from: env.get("OWNER_ALERT_FROM")?.trim() || DEFAULT_ALERT_FROM,
        to: recipients(env),
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
      }),
      signal: AbortSignal.timeout(deps.timeoutMs ?? 8_000),
    });
    if (!response.ok) {
      const detail = `HTTP ${response.status} ${(await response.text().catch(() => "")).slice(0, 200)}`.trim();
      console.warn("owner alert not sent:", detail);
      return { sent: false, reason: "failed", detail };
    }
    await response.body?.cancel();
    return { sent: true };
  } catch (error) {
    const detail = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    console.warn("owner alert not sent:", detail);
    return { sent: false, reason: "failed", detail };
  }
}

/**
 * Lets a task finish after the response went out (Supabase's EdgeRuntime.waitUntil
 * where it exists), never rejecting.
 */
export function runInBackground(task: Promise<unknown>): Promise<void> {
  const guarded = task.then(() => {}, (error) => {
    console.warn("owner alert failed:", error instanceof Error ? error.message : error);
  });
  try {
    (globalThis as { EdgeRuntime?: { waitUntil?(promise: Promise<unknown>): void } }).EdgeRuntime?.waitUntil?.(
      guarded,
    );
  } catch {
    // Without waitUntil the task still runs while the worker lives.
  }
  return guarded;
}

/** Constant-time comparison for shared secrets. */
export function secretsMatch(given: string | null, expected: string): boolean {
  const a = new TextEncoder().encode(given ?? "");
  const b = new TextEncoder().encode(expected);
  let difference = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) difference |= (a[i] ?? 0) ^ b[i];
  return difference === 0 && b.length > 0;
}
