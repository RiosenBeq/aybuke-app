// Owner alerts by email, sent with Resend (https://resend.com/docs/api-reference/emails/send-email).
//
//   RESEND_API_KEY    required; without it every alert is skipped (one log line, never an error)
//   OWNER_ALERT_TO    default hello@buaze.com (comma-separated for more than one)
//   OWNER_ALERT_FROM  default "Aybuke <onboarding@resend.dev>", which only delivers to the
//                     Resend account's own address until a domain is verified there
//
// The mails carry counts, plans and times only: never a user id, email, token,
// transaction id or prompt. The one exception is the daily digest's list of
// RevenueCat App User IDs of accounts already deleted, so the owner can delete
// those customers too (owner-digest/handler.ts). Everything interpolated is escaped.
//
// The design: the Blush palette (docs/02-brand-identity.md) in a 600 px table
// layout with the styles that matter inline, so Gmail, Outlook and Apple Mail
// draw the same mail. A <style> block adds the phone layout (one column under
// 480 px) and dark mode (prefers-color-scheme); Outlook.com's dark-mode hooks
// and Apple's data detectors sit in a second block, because Gmail drops a whole
// block it can't parse. Every coloured text sits on a table with a bgcolor, so
// clients that invert colours have a background to work from. No web fonts or
// images: the wordmark is live text, and every mail has a plain-text part with
// the same facts.

export interface Env {
  get(name: string): string | undefined;
}

export const RESEND_ENDPOINT = "https://api.resend.com/emails";
export const DEFAULT_ALERT_TO = "hello@buaze.com";
export const DEFAULT_ALERT_FROM = "Aybuke <onboarding@resend.dev>";

/** Light colours, inline. The dark ones are in DARK_CSS. */
const C = {
  page: "#F8E0EA", // petal
  card: "#FFFFFF",
  tile: "#FDF2F6",
  line: "#F3D9E4",
  blush: "#F7C1D9",
  blushLight: "#FBD3E2",
  peach: "#FFD9C7",
  ink: "#121212",
  soft: "#3B2A32", // ink, softened, for the summary on blush
  muted: "#6B5560",
  warn: "#B0144F",
  warnLine: "#F4B6CE",
  warnTint: "#FFF1F6",
  good: "#1C6E46",
  sparkle: "#C2477F",
  onInk: "#FBEFF4",
  inkRaised: "#2B2326",
  code: "#FBF3F6",
};
const SANS = "Poppins,'Avenir Next',Avenir,'Segoe UI','Helvetica Neue',Helvetica,Arial,sans-serif";
const MONO = "ui-monospace,SFMono-Regular,Menlo,Consolas,'Liberation Mono',monospace";

export type Value = string | number | boolean | null | undefined;

/** How a value reads: "warn" when it needs the owner, "good" when all is well. */
export type Tone = "warn" | "good";

export interface StatCard {
  label: string;
  value: Value;
  /** A small line under the number, e.g. "+7 today". */
  note?: string;
  tone?: Tone;
}

export interface DetailRow {
  label: string;
  value: Value;
  /** "code": a line to copy (SQL) in a monospace box; "note": a sentence under its label. */
  kind?: "code" | "note";
  tone?: Tone;
}

export interface MailSection {
  title: string;
  rows: DetailRow[];
  /** Numbered rows: what to do, in order. */
  steps?: boolean;
}

export interface MailAction {
  label: string;
  /** https only; anything else is dropped. */
  url: string;
}

/** What an owner mail says. Only these fields reach the mail. */
export interface OwnerMail {
  subject: string;
  /** The preview line inboxes show next to the subject (default: the summary). */
  preheader?: string;
  /** Small capitals above the headline, e.g. "New Pro member". */
  eyebrow: string;
  headline: string;
  /** The mail in one short line, under the headline. */
  summary: string;
  /** The header: blush to peach for good news, blush for news, ink for an alert. */
  tone?: "celebrate" | "info" | "alert";
  /** When it happened or was sent, top right in the header. */
  stamp?: string;
  /** A highlighted note under the summary, e.g. that a purchase was a sandbox test. */
  badge?: string;
  /** "Needs you": what to look at, most urgent first. */
  attention?: string[];
  stats: StatCard[];
  sections: MailSection[];
  actions?: MailAction[];
  /** Why the owner gets this mail, in the footer. */
  reason: string;
}

export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

export const FOOTER = "Owner alerts from your Aybuke backend, sent through Resend.";

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

/** Numbers grouped for reading (12,345). */
export function formatNumber(value: number): string {
  return Number.isFinite(value) ? value.toLocaleString("en-US") : "–";
}

/** Numbers grouped for reading (12,345); anything else as one line; nothing as a dash. */
export function formatValue(value: Value): string {
  if (typeof value === "number") return formatNumber(value);
  if (typeof value === "boolean") return value ? "Yes" : "No";
  const text = oneLine(value);
  return text || "–";
}

/** "1 report", "3 reports". */
export function plural(n: number, one: string, many = `${one}s`): string {
  return `${formatNumber(n)} ${n === 1 ? one : many}`;
}

function dateParts(date: Date, timeZone: string, options: Intl.DateTimeFormatOptions): Record<string, string> {
  return Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", { timeZone, ...options }).formatToParts(date).map((part) => [
      part.type,
      part.value,
    ]),
  );
}

/** "2026-10-15 06:00" in a time zone. */
function clock(date: Date, timeZone: string): string {
  const parts = dateParts(date, timeZone, {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`;
}

/** The same moment in UTC and in Istanbul. */
export function formatWhen(date: Date): { utc: string; istanbul: string } {
  return { utc: `${clock(date, "UTC")} UTC`, istanbul: `${clock(date, "Europe/Istanbul")} Istanbul` };
}

/** "15 Oct, 06:05 UTC": the header's stamp. */
export function formatStamp(date: Date): string {
  const parts = dateParts(date, "UTC", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  return `${parts.day} ${parts.month}, ${parts.hour}:${parts.minute} UTC`;
}

/** A UTC day (yyyy-MM-dd) as "14 Oct" and "Wednesday 14 October"; the day itself when it isn't one. */
export function formatDay(day: string): { short: string; long: string } {
  const date = new Date(`${day}T12:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || Number.isNaN(date.getTime())) return { short: day, long: day };
  const parts = dateParts(date, "UTC", { weekday: "long", day: "numeric", month: "long" });
  const short = dateParts(date, "UTC", { day: "numeric", month: "short" });
  return { short: `${short.day} ${short.month}`, long: `${parts.weekday} ${parts.day} ${parts.month}` };
}

// MARK: - HTML

/** Escaped, with break chances after ( , . so a long SQL line wraps; <wbr> isn't copied with the text. */
function codeHtml(value: Value): string {
  return escapeHtml(formatValue(value)).replace(/([(,.])/g, "$1<wbr>");
}

function toneClass(tone: Tone | undefined): { cls: string; color: string } {
  if (tone === "warn") return { cls: "gl-warn", color: C.warn };
  if (tone === "good") return { cls: "gl-good", color: C.good };
  return { cls: "gl-ink", color: C.ink };
}

function header(mail: OwnerMail): string {
  const alert = mail.tone === "alert";
  const bg = alert ? C.ink : C.blush;
  const gradient = alert
    ? ""
    : `background-image:linear-gradient(135deg,${C.blush} 0%,${C.blushLight} 55%,${
      mail.tone === "celebrate" ? C.peach : C.page
    } 100%);`;
  // The alert header is ink in both modes, so its text keeps its light colours (no dark classes).
  const [ink, soft, brand, sparkle] = alert
    ? [{ cls: "", color: C.onInk }, { cls: "", color: C.onInk }, { cls: "", color: C.blush }, {
      cls: "",
      color: C.blush,
    }]
    : [
      { cls: "gl-h-ink", color: C.ink },
      { cls: "gl-h-soft", color: C.soft },
      { cls: "gl-h-brand", color: C.ink },
      { cls: "gl-h-brand", color: C.sparkle },
    ];
  const badge = mail.badge
    ? `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;"><tr>
<td class="${alert ? "" : "gl-badge"}" bgcolor="${alert ? C.inkRaised : C.card}" style="background-color:${
      alert ? C.inkRaised : C.card
    };border:1px solid ${
      alert ? C.blush : C.ink
    };border-radius:14px;padding:7px 14px;font-family:${SANS};font-size:13px;line-height:19px;font-weight:600;color:${
      alert ? C.onInk : C.ink
    };">${escapeHtml(mail.badge)}</td>
</tr></table>`
    : "";
  const stamp = mail.stamp
    ? `<td align="right" valign="middle" class="${soft.cls}" style="font-family:${SANS};font-size:12px;line-height:16px;color:${soft.color};padding-left:12px;">${
      escapeHtml(mail.stamp)
    }</td>`
    : "";
  return `<tr><td class="gl-pad ${
    alert ? "" : "gl-head"
  }" bgcolor="${bg}" style="background-color:${bg};${gradient}border-radius:23px 23px 0 0;padding:26px 28px 26px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td valign="middle" style="font-family:${SANS};"><span class="${brand.cls}" style="font-family:${SANS};font-size:24px;line-height:28px;font-weight:700;letter-spacing:-0.6px;color:${brand.color};">aybuke</span><span class="${sparkle.cls}" aria-hidden="true" style="font-family:${SANS};font-size:15px;line-height:15px;vertical-align:top;color:${sparkle.color};padding-left:1px;">&#10022;</span></td>
${stamp}
</tr></table>
<p class="${ink.cls}" style="margin:0;padding-top:22px;font-family:${SANS};font-size:12px;line-height:16px;font-weight:700;letter-spacing:1.6px;text-transform:uppercase;color:${ink.color};">${
    escapeHtml(mail.eyebrow)
  }</p>
<h1 class="gl-headline ${ink.cls}" style="margin:0;padding-top:6px;font-family:${SANS};font-size:26px;line-height:33px;font-weight:700;color:${ink.color};">${
    escapeHtml(mail.headline)
  }</h1>
<p class="${soft.cls}" style="margin:0;padding-top:8px;font-family:${SANS};font-size:15px;line-height:23px;color:${soft.color};">${
    escapeHtml(mail.summary)
  }</p>
${badge}
</td></tr>`;
}

function attentionBlock(items: string[] | undefined): string {
  if (!items || items.length === 0) return "";
  const rows = items.map((item) =>
    `<tr><td width="18" valign="top" class="gl-warn" style="font-family:${SANS};font-size:15px;line-height:22px;color:${C.warn};">&#8226;</td>` +
    `<td class="gl-ink" style="font-family:${SANS};font-size:15px;line-height:22px;color:${C.ink};padding-bottom:4px;">${
      escapeHtml(item)
    }</td></tr>`
  ).join("");
  return `<tr><td class="gl-pad" style="padding:24px 28px 0;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td class="gl-attn" bgcolor="${C.warnTint}" style="background-color:${C.warnTint};border:1px solid ${C.warnLine};border-left:4px solid ${C.warn};border-radius:14px;padding:14px 16px 10px;">
<p class="gl-warn" style="margin:0 0 6px;font-family:${SANS};font-size:12px;line-height:16px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:${C.warn};">Needs you</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${rows}</table>
</td></tr></table>
</td></tr>`;
}

function tile(stat: StatCard): string {
  const value = toneClass(stat.tone);
  const border = stat.tone === "warn" ? C.warnLine : C.line;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td class="gl-tile${
    stat.tone === "warn" ? " gl-tile-warn" : ""
  }" bgcolor="${C.tile}" style="background-color:${C.tile};border:1px solid ${border};border-radius:16px;padding:16px 18px 15px;">
<p class="gl-muted" style="margin:0;font-family:${SANS};font-size:12px;line-height:16px;font-weight:600;letter-spacing:0.8px;text-transform:uppercase;color:${C.muted};">${
    escapeHtml(stat.label)
  }</p>
<p class="gl-kpi ${value.cls}" style="margin:0;padding-top:6px;font-family:${SANS};font-size:30px;line-height:36px;font-weight:700;letter-spacing:-0.5px;color:${value.color};">${
    escapeHtml(formatValue(stat.value))
  }</p>
<p class="gl-muted" style="margin:0;padding-top:2px;font-family:${SANS};font-size:13px;line-height:19px;color:${C.muted};">${
    stat.note ? escapeHtml(oneLine(stat.note)) : "&nbsp;"
  }</p>
</td></tr></table>`;
}

function statGrid(stats: StatCard[]): string {
  if (stats.length === 0) return "";
  const rows: string[] = [];
  for (let i = 0; i < stats.length; i += 2) {
    const [left, right] = [stats[i], stats[i + 1]];
    rows.push(`<tr>
<td class="gl-col" width="50%" valign="top" style="padding:0 6px 12px 0;">${tile(left)}</td>
<td class="gl-col" width="50%" valign="top" style="padding:0 0 12px 6px;">${right ? tile(right) : "&nbsp;"}</td>
</tr>`);
  }
  return `<tr><td class="gl-pad" style="padding:24px 28px 0;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${rows.join("")}</table>
</td></tr>`;
}

function stepCell(step: number | undefined): string {
  if (step === undefined) return "";
  return `<td width="34" valign="top" style="padding-right:10px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td class="gl-step" bgcolor="${C.blush}" width="24" height="24" align="center" style="background-color:${C.blush};width:24px;height:24px;border-radius:12px;font-family:${SANS};font-size:12px;line-height:24px;font-weight:700;color:${C.ink};text-align:center;">${step}</td></tr></table>
</td>`;
}

function rowHtml(row: DetailRow, step: number | undefined, last: boolean): string {
  const value = toneClass(row.tone);
  const label = escapeHtml(row.label);
  let inner: string;
  if (row.kind === "code") {
    inner = `<td valign="top">
<p class="gl-muted" style="margin:0;font-family:${SANS};font-size:14px;line-height:21px;color:${C.muted};">${label}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:6px;"><tr>
<td class="gl-code" bgcolor="${C.code}" style="background-color:${C.code};border:1px solid ${C.line};border-radius:10px;padding:10px 12px;font-family:${MONO};font-size:13px;line-height:20px;color:${C.ink};word-wrap:break-word;overflow-wrap:anywhere;">${
      codeHtml(row.value)
    }</td>
</tr></table>
</td>`;
  } else if (row.kind === "note") {
    inner = `<td valign="top">
<p class="gl-muted" style="margin:0;font-family:${SANS};font-size:14px;line-height:21px;color:${C.muted};">${label}</p>
<p class="${value.cls}" style="margin:0;padding-top:3px;font-family:${SANS};font-size:15px;line-height:22px;color:${value.color};">${
      escapeHtml(formatValue(row.value))
    }</p>
</td>`;
  } else {
    inner =
      `<td class="gl-muted" valign="top" style="font-family:${SANS};font-size:14px;line-height:21px;color:${C.muted};padding-right:12px;">${label}</td>
<td class="${value.cls}" valign="top" align="right" style="font-family:${SANS};font-size:15px;line-height:21px;font-weight:600;color:${value.color};text-align:right;white-space:nowrap;">${
        escapeHtml(formatValue(row.value))
      }</td>`;
  }
  const border = last ? "" : `border-bottom:1px solid ${C.line};`;
  return `<tr><td class="${last ? "" : "gl-line"}" style="${border}padding:11px 0;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>${
    stepCell(step)
  }${inner}</tr></table>
</td></tr>`;
}

function sectionBlock(section: MailSection): string {
  const rows = section.rows.map((row, i) =>
    rowHtml(row, section.steps ? i + 1 : undefined, i === section.rows.length - 1)
  )
    .join("");
  return `<tr><td class="gl-pad" style="padding:22px 28px 0;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
<tr><td class="gl-ink gl-title" style="font-family:${SANS};font-size:13px;line-height:18px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:${C.ink};padding:0 0 9px;border-bottom:2px solid ${C.blush};">${
    escapeHtml(section.title)
  }</td></tr>
${rows}
</table>
</td></tr>`;
}

function safeActions(actions: MailAction[] | undefined): MailAction[] {
  return (actions ?? []).filter((action) => /^https:\/\/[^\s"'<>]+$/.test(action.url));
}

/** Buttons side by side where they fit, wrapping where they don't (Outlook stacks them); full width on phones. */
function actionsBlock(actions: MailAction[]): string {
  if (actions.length === 0) return "";
  const buttons = actions.map((action) =>
    `<table role="presentation" cellpadding="0" cellspacing="0" border="0" class="gl-btn" style="display:inline-table;vertical-align:top;margin:0 8px 10px 0;"><tr>
<td class="gl-btn-bg" bgcolor="${C.ink}" align="center" style="background-color:${C.ink};border-radius:999px;mso-padding-alt:14px 24px;">
<a class="gl-btn-text" href="${
      escapeHtml(action.url)
    }" target="_blank" rel="noopener" style="display:inline-block;padding:14px 24px;font-family:${SANS};font-size:15px;line-height:20px;font-weight:600;color:${C.page};text-decoration:none;white-space:nowrap;border-radius:999px;">${
      escapeHtml(action.label)
    } &#8594;</a>
</td></tr></table>`
  ).join("\n");
  return `<tr><td class="gl-pad" style="padding:24px 28px 0;">
${buttons}
</td></tr>`;
}

function footer(mail: OwnerMail): string {
  return `<tr><td class="gl-pad gl-foot" bgcolor="${C.tile}" style="background-color:${C.tile};border-top:1px solid ${C.line};border-radius:0 0 23px 23px;padding:20px 28px 24px;">
<p class="gl-muted" style="margin:0;font-family:${SANS};font-size:13px;line-height:20px;color:${C.muted};">${
    escapeHtml(mail.reason)
  }</p>
<p class="gl-muted" style="margin:0;padding-top:10px;font-family:${SANS};font-size:12px;line-height:18px;color:${C.muted};"><span class="gl-ink" style="font-weight:700;color:${C.ink};">aybuke</span> &#183; ${FOOTER}</p>
</td></tr>`;
}

/** Responsive and dark-mode rules: progressive enhancement over the inline styles. */
const MAIN_CSS =
  `body{margin:0!important;padding:0!important;width:100%!important;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}
table{border-collapse:separate;mso-table-lspace:0pt;mso-table-rspace:0pt;}
.gl-code{word-wrap:break-word;overflow-wrap:anywhere;}
@media only screen and (max-width:480px){
.gl-outer{padding:12px 8px!important;}
.gl-pad{padding-left:18px!important;padding-right:18px!important;}
.gl-col{display:block!important;width:100%!important;max-width:100%!important;box-sizing:border-box;padding:0 0 10px 0!important;}
.gl-headline{font-size:22px!important;line-height:29px!important;}
.gl-kpi{font-size:26px!important;line-height:32px!important;}
.gl-btn{display:table!important;width:100%!important;margin:0 0 10px 0!important;}
.gl-btn-text{display:block!important;}
}
@media (prefers-color-scheme:dark){
.gl-page{background-color:#171113!important;}
.gl-card{background-color:#221A1E!important;border-color:#3B2F35!important;}
.gl-head{background-color:#3A2531!important;background-image:none!important;}
.gl-h-ink{color:#F7EDF1!important;}
.gl-h-soft{color:#E5D3DB!important;}
.gl-h-brand{color:#F7C1D9!important;}
.gl-badge{background-color:#221A1E!important;border-color:#F7C1D9!important;color:#F7EDF1!important;}
.gl-tile,.gl-foot{background-color:#2D2328!important;border-color:#3B2F35!important;}
.gl-tile-warn{border-color:#FF9DC2!important;}
.gl-attn{background-color:#2D1A22!important;border-color:#FF9DC2!important;}
.gl-line,.gl-title{border-color:#3B2F35!important;}
.gl-title{border-bottom-color:#7A4A60!important;}
.gl-ink{color:#F7EDF1!important;}
.gl-muted{color:#D2BBC6!important;}
.gl-warn{color:#FF9DC2!important;}
.gl-good{color:#86D9AE!important;}
.gl-code{background-color:#1A1316!important;border-color:#3B2F35!important;color:#F7EDF1!important;}
.gl-step,.gl-btn-bg{background-color:#F7C1D9!important;color:#121212!important;}
.gl-btn-text{color:#121212!important;}
}`;

/** Outlook.com's dark mode marks what it recoloured with data-ogsc/data-ogsb; Apple Mail links dates and numbers. */
const CLIENT_CSS = `:root{color-scheme:light dark;supported-color-schemes:light dark;}
a[x-apple-data-detectors]{color:inherit!important;text-decoration:none!important;font-size:inherit!important;font-family:inherit!important;font-weight:inherit!important;line-height:inherit!important;}
[data-ogsb] .gl-page{background-color:#171113!important;}
[data-ogsb] .gl-card{background-color:#221A1E!important;}
[data-ogsb] .gl-head{background-color:#3A2531!important;background-image:none!important;}
[data-ogsb] .gl-tile,[data-ogsb] .gl-foot{background-color:#2D2328!important;}
[data-ogsb] .gl-code{background-color:#1A1316!important;}
[data-ogsb] .gl-attn{background-color:#2D1A22!important;}
[data-ogsc] .gl-ink,[data-ogsc] .gl-h-ink{color:#F7EDF1!important;}
[data-ogsc] .gl-h-soft{color:#E5D3DB!important;}
[data-ogsc] .gl-h-brand{color:#F7C1D9!important;}
[data-ogsc] .gl-muted{color:#D2BBC6!important;}
[data-ogsc] .gl-warn{color:#FF9DC2!important;}
[data-ogsc] .gl-good{color:#86D9AE!important;}`;

/** Table layout, inline styles, 600 px: what Gmail, Outlook and Apple Mail all render. */
function renderHtml(mail: OwnerMail): string {
  const subject = escapeHtml(oneLine(mail.subject));
  const preheader = escapeHtml(oneLine(mail.preheader ?? mail.summary));
  return `<!doctype html>
<html lang="en" dir="ltr" xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${subject}</title>
<!--[if mso]><noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript><![endif]-->
<!--[if mso]><style>table,td,p,h1,a,span{font-family:Arial,Helvetica,sans-serif!important;}</style><![endif]-->
<style>
${MAIN_CSS}
</style>
<style>
${CLIENT_CSS}
</style>
</head>
<body class="gl-page" bgcolor="${C.page}" style="margin:0;padding:0;background-color:${C.page};">
<div style="display:none;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">${preheader}${
    "&#847;&zwnj;&nbsp;".repeat(40)
  }</div>
<div role="article" aria-roledescription="email" aria-label="${subject}" lang="en" dir="ltr">
<table role="presentation" class="gl-page" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.page}" style="background-color:${C.page};">
<tr><td class="gl-outer" align="center" style="padding:28px 12px;">
<!--[if mso]><table role="presentation" align="center" width="600" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" class="gl-card" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.card}" style="width:100%;max-width:600px;background-color:${C.card};border:1px solid ${C.line};border-radius:24px;">
${header(mail)}
${attentionBlock(mail.attention)}
${statGrid(mail.stats)}
${mail.sections.map(sectionBlock).join("\n")}
${actionsBlock(safeActions(mail.actions))}
<tr><td style="height:28px;font-size:0;line-height:0;">&nbsp;</td></tr>
${footer(mail)}
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr>
</table>
</div>
</body>
</html>`;
}

// MARK: - Plain text

function renderText(mail: OwnerMail): string {
  const lines = [`aybuke · ${oneLine(mail.eyebrow)}`];
  if (mail.stamp) lines.push(oneLine(mail.stamp));
  lines.push("", oneLine(mail.headline), oneLine(mail.summary));
  if (mail.badge) lines.push(`[${oneLine(mail.badge)}]`);
  if (mail.attention && mail.attention.length > 0) {
    lines.push("", "NEEDS YOU");
    for (const item of mail.attention) lines.push(`  - ${oneLine(item)}`);
  }
  if (mail.stats.length > 0) {
    lines.push("");
    for (const stat of mail.stats) {
      const note = stat.note ? ` (${oneLine(stat.note)})` : "";
      lines.push(`${oneLine(stat.label)}: ${formatValue(stat.value)}${note}`);
    }
  }
  for (const section of mail.sections) {
    lines.push("", oneLine(section.title).toUpperCase());
    section.rows.forEach((row, i) => {
      lines.push(`  ${section.steps ? `${i + 1}. ` : ""}${oneLine(row.label)}: ${formatValue(row.value)}`);
    });
  }
  const actions = safeActions(mail.actions);
  if (actions.length > 0) {
    lines.push("");
    for (const action of actions) lines.push(`${oneLine(action.label)}: ${oneLine(action.url)}`);
  }
  lines.push("", "--", oneLine(mail.reason), FOOTER);
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
