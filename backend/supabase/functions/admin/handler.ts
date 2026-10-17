// The owner's admin API, for the admin page on aybuke.org (backend/README.md
// "Admin API", migration 20261105100000_admin_api.sql).
//
//   GET  /admin/overview    → { generated_at, today, members, budget, polls, ai }
//   GET  /admin/moderation  → { poll_reports, reports, strikes }
//   GET  /admin/audit       → { entries: [{ at, action, target?, address, outcome }] }   (last 50)
//   POST /admin/action      { action, target? } → { ok: true, result }
//
// A request gets in one of two ways:
//   - the owner's Supabase Auth session: `Authorization: Bearer <access token>`
//     of a user whose email is in ADMIN_EMAILS (comma-separated, any case),
//     confirmed, signed in with the email provider's password and not
//     anonymous. The token's own claims can refuse it (anonymous, another
//     email, expired); only the auth server's answer (auth.getUser) admits
//     it. A real session of anyone else is a 403 forbidden.
//   - x-admin-token, with the public anon key as the bearer: SHA-256 of the
//     token is compared in constant time with ADMIN_TOKEN_SHA256 (hex).
// With neither secret set every call is a 503 admin_disabled. admin_gate()
// then counts the request: 60 a minute per address, and 5 refused requests
// (a wrong or missing token, an ended session, someone else's session) within
// 15 minutes lock the address out for 15 minutes.
// Answers name nobody: users, installs and addresses are short salted tags
// ('u-', 'i-', 'a-' and 12 hex characters), and a last pass drops anything
// that still looks like an id, a key, an address or an email. Logs carry the
// route, the outcome and the time taken, never a token, an email, an id or an
// address.

export interface RpcResult {
  data: unknown;
  error: { message: string } | null;
}

export interface AdminDeps {
  env: { get(name: string): string | undefined };
  /** A database function, with the service role. */
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<RpcResult>;
  /**
   * The auth server's user for an access token (auth.getUser with the service
   * role): null when it doesn't accept the token; throws when it can't be asked.
   */
  getUser(jwt: string): Promise<SessionUser | null>;
  /** The caller's address bucket (clientIp() in _shared/input.ts). */
  clientIp(req: Request): string | undefined;
  now(): Date;
  /** Route, outcome and timings only. */
  log(entry: Record<string, unknown>): void;
}

/** The parts of a Supabase Auth user the session check reads. */
export interface SessionUser {
  id: string;
  email?: string | null;
  email_confirmed_at?: string | null;
  is_anonymous?: boolean;
  app_metadata?: { provider?: string; providers?: string[] };
}

export type SessionVerdict = "none" | "invalid" | "forbidden" | "admin";

export const ACTIONS = ["pause_ai", "resume_ai", "take_down_poll", "restore_poll", "block", "unblock"] as const;
export type Action = typeof ACTIONS[number];

const SITE_ORIGINS = new Set(["https://aybuke.org", "https://www.aybuke.org"]);
const LOCAL_ORIGIN = /^http:\/\/localhost(:\d{1,5})?$/;
const POLL_ID = /^[A-Za-z0-9_-]{16}$/;
const TARGET_TAG = /^[iu]-[0-9a-f]{12}$/;
const SHORT_HEX = /^[0-9a-f]{12}$/;
const MAX_TOKEN = 512;
const MAX_BODY = 1024;
const MAX_JWT = 8192;

const MESSAGES: Record<string, string> = {
  origin_not_allowed: "This origin can't use the admin API.",
  admin_disabled: "The admin API is off.",
  unauthorized: "Wrong or missing admin token.",
  session_expired: "Your session has ended. Sign in again.",
  forbidden: "This account isn't an admin.",
  locked_out: "Too many wrong tokens. Try again later.",
  rate_limited: "Too many requests. Try again in a minute.",
  unavailable: "The admin API can't check requests right now.",
  bad_request: "That request doesn't look right.",
  not_found: "Not found.",
  ambiguous: "That tag matches more than one; nothing was changed.",
  method_not_allowed: "Method not allowed.",
  internal: "Something went wrong.",
};

class AdminError extends Error {
  constructor(readonly status: number, readonly code: string, readonly retryAfter?: number) {
    super(MESSAGES[code] ?? MESSAGES.internal);
  }
}

// MARK: - CORS

export function allowedOrigin(origin: string | null): boolean {
  return origin !== null && (SITE_ORIGINS.has(origin) || LOCAL_ORIGIN.test(origin));
}

function corsHeaders(origin: string | null): Record<string, string> {
  return allowedOrigin(origin)
    ? { "Access-Control-Allow-Origin": origin!, "Access-Control-Expose-Headers": "Retry-After" }
    : {};
}

const PREFLIGHT: Record<string, string> = {
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-admin-token",
  "Access-Control-Max-Age": "600",
};

function respond(
  body: unknown,
  status: number,
  origin: string | null,
  extra: Record<string, string> = {},
): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: {
      ...(body === null ? {} : { "Content-Type": "application/json; charset=utf-8" }),
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      Vary: "Origin",
      ...corsHeaders(origin),
      ...extra,
    },
  });
}

function failure(error: AdminError, origin: string | null): Response {
  const body: Record<string, unknown> = { code: error.code, message: error.message };
  const headers: Record<string, string> = {};
  if (error.retryAfter !== undefined) {
    body.retry_after = error.retryAfter;
    headers["Retry-After"] = String(error.retryAfter);
  }
  if (error.status === 405) headers.Allow = "GET, POST, OPTIONS";
  return respond({ error: body }, error.status, origin, headers);
}

// MARK: - Token

/** Equal length and bytes, in time that depends only on the lengths. */
export function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return difference === 0;
}

/** ADMIN_TOKEN_SHA256 as 32 bytes, or undefined when it's missing or isn't 64 hex characters. */
export function parseDigest(hex: string | undefined): Uint8Array | undefined {
  const value = hex?.trim().toLowerCase() ?? "";
  if (!/^[0-9a-f]{64}$/.test(value)) return undefined;
  return Uint8Array.from(value.match(/../g)!, (pair) => parseInt(pair, 16));
}

/** SHA-256 of the given token against the expected digest. A missing, empty or oversized token never matches. */
export async function tokenMatches(token: string | null, expected: Uint8Array): Promise<boolean> {
  const given = token ?? "";
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(given.slice(0, MAX_TOKEN))),
  );
  return constantTimeEqual(digest, expected) && given.length > 0 && given.length <= MAX_TOKEN;
}

// MARK: - The owner's session

/** ADMIN_EMAILS as a set: comma-separated, trimmed, lowercased, empty entries dropped. */
export function parseAdminEmails(value: string | undefined): Set<string> {
  return new Set((value ?? "").split(",").map((email) => email.trim().toLowerCase()).filter((email) => email !== ""));
}

/** A JWT's payload, not verified, or null when the value isn't a JWT. */
export function jwtClaims(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length !== 3 || token.length > MAX_JWT || !/^[A-Za-z0-9_-]+$/.test(parts[1])) return null;
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const binary = atob(base64 + "=".repeat((4 - base64.length % 4) % 4));
    return record(JSON.parse(new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)))));
  } catch {
    return null;
  }
}

function normalizedEmail(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

/** The session was opened with a password (amr), not a link, a code or another provider. */
function openedWithPassword(claims: Record<string, unknown>): boolean {
  return Array.isArray(claims.amr) && claims.amr.some((entry) => record(entry)?.method === "password");
}

/** The auth server's user: an admin email, confirmed, an email-provider account, not anonymous. */
export function isAdminUser(user: SessionUser, admins: Set<string>): boolean {
  const email = normalizedEmail(user.email);
  const providers = Array.isArray(user.app_metadata?.providers) ? user.app_metadata.providers : [];
  return user.is_anonymous !== true && email !== "" && admins.has(email) &&
    typeof user.email_confirmed_at === "string" && user.email_confirmed_at !== "" &&
    (user.app_metadata?.provider === "email" || providers.includes("email"));
}

/**
 * What the bearer says about the caller: "none" (no session: the anon key, the
 * service role, nothing), "invalid" (expired, malformed or unknown to the auth
 * server), "forbidden" (a real session of someone who isn't an admin) or
 * "admin". Claims alone may refuse; only the auth server admits, and it's asked
 * only for a token that claims to be an admin's. Throws when it can't answer.
 */
export async function checkSession(req: Request, deps: AdminDeps, admins: Set<string>): Promise<SessionVerdict> {
  const bearer = /^Bearer\s+(\S+)$/i.exec(req.headers.get("Authorization") ?? "")?.[1] ?? "";
  const claims = bearer ? jwtClaims(bearer) : null;
  if (!claims || claims.role !== "authenticated") return "none";
  if (typeof claims.sub !== "string" || claims.sub === "") return "invalid";
  if (typeof claims.exp !== "number" || claims.exp * 1000 <= deps.now().getTime()) return "invalid";
  if (claims.is_anonymous === true || !admins.has(normalizedEmail(claims.email)) || !openedWithPassword(claims)) {
    return "forbidden";
  }
  const user = await deps.getUser(bearer);
  if (!user || user.id !== claims.sub) return "invalid";
  return isAdminUser(user, admins) ? "admin" : "forbidden";
}

// MARK: - Answers without PII

/** Keys that must never reach the page, wherever they appear. */
const DENIED_KEYS = new Set([
  "user_id",
  "user_ids",
  "install_key",
  "ip",
  "ip_key",
  "email",
  "job_id",
  "report_id",
  "app_user_id",
  "app_user_ids",
  "transaction_id",
  "original_transaction_id",
]);
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const LONG_HEX = /\b[0-9a-f]{20,}\b/gi;
const EMAIL = /[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[a-z]{2,}/gi;
const IPV4 = /\b\d{1,3}(?:\.\d{1,3}){3}\b/g;
const IPV6 = /\b(?:[0-9a-f]{1,4}:){3,7}(?::|[0-9a-f]{1,4})(?:\/\d{1,3})?/gi;

/** A string with ids, keys, emails and addresses replaced by placeholders. */
export function redact(text: string): string {
  return text
    .replace(EMAIL, "[email]")
    .replace(UUID, "[id]")
    .replace(LONG_HEX, "[key]")
    .replace(IPV6, "[address]")
    .replace(IPV4, "[address]");
}

/** The whole answer without denied keys, and every string through redact(). */
export function scrub(value: unknown): unknown {
  if (typeof value === "string") return redact(value);
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) {
      if (!DENIED_KEYS.has(key)) out[key] = scrub(item);
    }
    return out;
  }
  return value;
}

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

/** ops_daily_summary()'s top installs and addresses (12 hex of a salted hash) as tags. */
export function tagTops(daily: unknown): unknown {
  const today = record(daily);
  if (!today) return daily;
  const tops = (list: unknown, key: string, prefix: string, count: string) =>
    (Array.isArray(list) ? list : []).flatMap((item) => {
      const entry = record(item);
      const value = entry?.[key];
      return typeof value === "string" && SHORT_HEX.test(value)
        ? [{ tag: prefix + value, [count]: entry![count] }]
        : [];
    });
  return {
    ...today,
    top_installs: tops(today.top_installs, "install", "i-", "jobs"),
    top_ips: tops(today.top_ips, "ip", "a-", "requests"),
  };
}

// MARK: - Requests

export interface ActionRequest {
  action: Action;
  target: string | null;
}

/** The action body, strictly: only `action` and `target`, each as the action needs it. */
export function parseAction(body: unknown): ActionRequest {
  const fields = record(body);
  if (!fields || Object.keys(fields).some((key) => key !== "action" && key !== "target")) {
    throw new AdminError(400, "bad_request");
  }
  const { action, target } = fields;
  if (typeof action !== "string" || !(ACTIONS as readonly string[]).includes(action)) {
    throw new AdminError(400, "bad_request");
  }
  if (target !== undefined && target !== null && typeof target !== "string") throw new AdminError(400, "bad_request");
  const value = typeof target === "string" ? target : null;
  const valid = (() => {
    switch (action as Action) {
      case "pause_ai":
      case "resume_ai":
        return value === null || value === "all" || value === "free";
      case "take_down_poll":
      case "restore_poll":
        return value !== null && POLL_ID.test(value);
      case "block":
      case "unblock":
        return value !== null && TARGET_TAG.test(value);
    }
  })();
  if (!valid) throw new AdminError(400, "bad_request");
  return { action: action as Action, target: value };
}

async function readJson(req: Request): Promise<unknown> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY) throw new AdminError(400, "bad_request");
  const text = await req.text();
  if (text.length > MAX_BODY) throw new AdminError(400, "bad_request");
  try {
    return JSON.parse(text);
  } catch {
    throw new AdminError(400, "bad_request");
  }
}

async function call(deps: AdminDeps, fn: string, args?: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await deps.rpc(fn, args);
  if (error) throw new Error(`${fn} failed`);
  return data;
}

/** A section of the overview, or null when it can't be read (the page shows dashes). */
async function section(deps: AdminDeps, fn: string, args?: Record<string, unknown>): Promise<unknown> {
  try {
    return await call(deps, fn, args) ?? null;
  } catch {
    deps.log({ fn: "admin", route: "overview", outcome: `section_unavailable:${fn}` });
    return null;
  }
}

async function overview(deps: AdminDeps): Promise<unknown> {
  const now = deps.now();
  const day = now.toISOString().slice(0, 10);
  const [today, members, budget, polls, ai] = await Promise.all([
    section(deps, "ops_daily_summary", { p_day: day }),
    section(deps, "ops_members_summary"),
    section(deps, "ops_provider_budget", { p_provider: "xai" }),
    section(deps, "ops_polls_summary", { p_day: day }),
    section(deps, "admin_ai_state"),
  ]);
  return { generated_at: now.toISOString(), today: tagTops(today), members, budget, polls, ai };
}

async function moderation(deps: AdminDeps): Promise<unknown> {
  const data = record(await call(deps, "admin_moderation", { p_days: 7 }));
  if (!data) throw new Error("admin_moderation answered nothing");
  const list = (key: string) => Array.isArray(data[key]) ? data[key] : [];
  return { poll_reports: list("poll_reports"), reports: list("reports"), strikes: list("strikes") };
}

async function audit(deps: AdminDeps): Promise<unknown> {
  const entries = await call(deps, "admin_audit_recent", { p_limit: 50 });
  return { entries: Array.isArray(entries) ? entries : [] };
}

async function act(req: Request, deps: AdminDeps): Promise<unknown> {
  const { action, target } = parseAction(await readJson(req));
  const answer = record(
    await call(deps, "admin_action", {
      p_action: action,
      p_target: target,
      p_ip: deps.clientIp(req) ?? null,
    }),
  );
  if (!answer) throw new Error("admin_action answered nothing");
  if (answer.ok !== true) {
    const status = typeof answer.status === "number" ? answer.status : 500;
    throw new AdminError(status, typeof answer.code === "string" ? answer.code : "internal");
  }
  return { ok: true, result: answer.result ?? null };
}

const ROUTES: Record<string, { method: string; run(req: Request, deps: AdminDeps): Promise<unknown> }> = {
  overview: { method: "GET", run: (_req, deps) => overview(deps) },
  moderation: { method: "GET", run: (_req, deps) => moderation(deps) },
  audit: { method: "GET", run: (_req, deps) => audit(deps) },
  action: { method: "POST", run: act },
};

/** The part of the path after the function's name: /functions/v1/admin/overview → "overview". */
export function routeOf(url: URL): string {
  const parts = url.pathname.split("/").filter(Boolean);
  const at = parts.lastIndexOf("admin");
  return at === -1 ? "" : parts.slice(at + 1).join("/");
}

/** Lets the request through the gate, or throws the refusal. */
async function admit(
  req: Request,
  deps: AdminDeps,
  expected: Uint8Array | undefined,
  admins: Set<string>,
): Promise<void> {
  const tokenOk = expected !== undefined && await tokenMatches(req.headers.get("x-admin-token"), expected);
  let session: SessionVerdict = "none";
  if (!tokenOk) {
    try {
      session = await checkSession(req, deps, admins);
    } catch {
      // The auth server can't say who this is: refuse, and don't count it against the address.
      throw new AdminError(503, "unavailable", 30);
    }
  }
  const admitted = tokenOk || session === "admin";
  let gate: Record<string, unknown> | null;
  try {
    gate = record(await call(deps, "admin_gate", { p_ip: deps.clientIp(req) ?? null, p_token_ok: admitted }));
  } catch {
    // Without the gate a refusal can't be counted: refuse everything.
    throw new AdminError(503, "unavailable", 30);
  }
  if (gate?.ok === true && admitted) return;
  const code = gate?.code;
  if (code === "locked_out" || code === "rate_limited") {
    throw new AdminError(429, code, typeof gate?.retry_after === "number" ? gate.retry_after : 60);
  }
  if (session === "forbidden") throw new AdminError(403, "forbidden");
  if (session === "invalid") throw new AdminError(401, "session_expired");
  throw new AdminError(401, "unauthorized");
}

export async function handleAdmin(req: Request, deps: AdminDeps): Promise<Response> {
  const started = performance.now();
  const origin = req.headers.get("Origin");
  const url = new URL(req.url);
  const route = routeOf(url);
  const done = (response: Response, outcome: string) => {
    deps.log({
      fn: "admin",
      route: Object.hasOwn(ROUTES, route) ? route : "other",
      outcome,
      status: response.status,
      ms: Math.round(performance.now() - started),
    });
    return response;
  };

  if (origin !== null && !allowedOrigin(origin)) {
    return done(failure(new AdminError(403, "origin_not_allowed"), origin), "origin_not_allowed");
  }
  if (req.method === "OPTIONS") return done(respond(null, 204, origin, PREFLIGHT), "preflight");

  try {
    const expected = parseDigest(deps.env.get("ADMIN_TOKEN_SHA256"));
    const admins = parseAdminEmails(deps.env.get("ADMIN_EMAILS"));
    if (!expected && admins.size === 0) throw new AdminError(503, "admin_disabled");
    await admit(req, deps, expected, admins);
    const handler = Object.hasOwn(ROUTES, route) ? ROUTES[route] : undefined;
    if (!handler) throw new AdminError(404, "not_found");
    if (req.method !== handler.method) throw new AdminError(405, "method_not_allowed");
    const body = scrub(await handler.run(req, deps));
    return done(respond(body, 200, origin), "ok");
  } catch (error) {
    if (error instanceof AdminError) return done(failure(error, origin), error.code);
    console.error("admin: unhandled error", error instanceof Error ? error.message : "unknown");
    return done(failure(new AdminError(500, "internal"), origin), "internal");
  }
}
