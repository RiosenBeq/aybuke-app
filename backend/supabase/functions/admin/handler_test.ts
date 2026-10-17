// deno test admin/
// The admin API with the database and the auth server faked: the token, the
// owner's session and the gate, CORS, each route, strict actions, and answers
// and logs that name nobody.
import assert from "node:assert/strict";
import {
  type AdminDeps,
  allowedOrigin,
  constantTimeEqual,
  handleAdmin,
  isAdminUser,
  jwtClaims,
  parseAction,
  parseAdminEmails,
  parseDigest,
  redact,
  routeOf,
  scrub,
  type SessionUser,
  tokenMatches,
} from "./handler.ts";

const TOKEN = "owner-token-for-tests-0123456789abcdefghijklmnopqrstuvwxyz-ABCDEFGH";
const NOW = new Date(Date.UTC(2026, 9, 17, 9, 30));
const SITE = "https://aybuke.org";
const USER_ID = "3f2a9c1e-7b4d-4e8a-9c21-5d6e7f809a1b";
const INSTALL_KEY = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";
const IP = "203.0.113.7";

async function sha256Hex(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
const TOKEN_SHA256 = await sha256Hex(TOKEN);

const OWNER_EMAIL = "info@nextgenlab.com.tr";
const OWNER_ID = "0b6c1f2e-4d3a-4f5b-8e7d-9a1b2c3d4e5f";
const NOW_SECONDS = Math.floor(NOW.getTime() / 1000);

function base64url(text: string): string {
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** A Supabase access token's shape (the signature is the gateway's business, not the function's). */
function jwt(claims: Record<string, unknown>): string {
  return `${base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${base64url(JSON.stringify(claims))}.c2lnbmF0dXJl`;
}

/** The owner's session after a password sign-in, with any claim replaced. */
function ownerJwt(overrides: Record<string, unknown> = {}): string {
  return jwt({
    sub: OWNER_ID,
    role: "authenticated",
    aud: "authenticated",
    email: OWNER_EMAIL,
    is_anonymous: false,
    exp: NOW_SECONDS + 3600,
    amr: [{ method: "password", timestamp: NOW_SECONDS - 60 }],
    ...overrides,
  });
}

/** The owner as the auth server knows them, with any field replaced. */
function ownerUser(overrides: Partial<SessionUser> = {}): SessionUser {
  return {
    id: OWNER_ID,
    email: OWNER_EMAIL,
    email_confirmed_at: "2026-10-17T08:00:00Z",
    is_anonymous: false,
    app_metadata: { provider: "email", providers: ["email"] },
    ...overrides,
  };
}

const ANON_KEY = jwt({ role: "anon", iss: "supabase", exp: NOW_SECONDS + 10 * 365 * 86400 });
const SESSION_ENV = { ADMIN_EMAILS: " Info@NextGenLab.com.tr ,, someone.else@example.com " };

/** admin_gate() as the migration has it: 60 a minute, 5 misses lock for 15 minutes, the right token forgives. */
class FakeGate {
  failures = new Map<string, number>();
  locked = new Set<string>();
  requests = new Map<string, number>();

  call(ip: string | null, tokenOk: boolean): Record<string, unknown> {
    const key = ip ?? "unknown";
    if (this.locked.has(key)) return { ok: false, code: "locked_out", status: 429, retry_after: 900 };
    const requests = (this.requests.get(key) ?? 0) + 1;
    this.requests.set(key, requests);
    if (requests > 60) return { ok: false, code: "rate_limited", status: 429, retry_after: 30 };
    if (tokenOk) {
      this.failures.delete(key);
      return { ok: true };
    }
    const failures = (this.failures.get(key) ?? 0) + 1;
    this.failures.set(key, failures);
    if (failures >= 5) this.locked.add(key);
    return { ok: false, code: "unauthorized", status: 401 };
  }
}

interface Call {
  fn: string;
  args?: Record<string, unknown>;
}

function fake(options: {
  env?: Record<string, string>;
  data?: Record<string, unknown>;
  fail?: string[];
  ip?: string | null;
  /** What the auth server answers for each access token (null: it doesn't accept it; "down": it can't be asked). */
  users?: Record<string, SessionUser | null | "down">;
} = {}) {
  const gate = new FakeGate();
  const calls: Call[] = [];
  const logs: Record<string, unknown>[] = [];
  const authCalls: string[] = [];
  const env = options.env ?? { ADMIN_TOKEN_SHA256: TOKEN_SHA256 };
  const deps: AdminDeps = {
    env: { get: (name) => env[name] },
    getUser: (token) => {
      authCalls.push(token);
      const user = options.users?.[token];
      if (user === "down") return Promise.reject(new Error("auth unavailable"));
      return Promise.resolve(user ?? null);
    },
    rpc: (fn, args) => {
      calls.push({ fn, args });
      if (options.fail?.includes(fn)) return Promise.resolve({ data: null, error: { message: `boom ${USER_ID}` } });
      if (fn === "admin_gate") {
        return Promise.resolve({
          data: gate.call(args?.p_ip as string | null, args?.p_token_ok === true),
          error: null,
        });
      }
      return Promise.resolve({ data: options.data?.[fn] ?? null, error: null });
    },
    // A test can name another address with x-test-ip.
    clientIp: (req) => req.headers.get("x-test-ip") ?? (options.ip === undefined ? IP : options.ip ?? undefined),
    now: () => NOW,
    log: (entry) => logs.push(entry),
  };
  return { deps, calls, logs, gate, authCalls };
}

function request(
  path: string,
  init: {
    method?: string;
    token?: string | null;
    origin?: string | null;
    body?: unknown;
    ip?: string;
    bearer?: string;
  } = {},
): Request {
  const headers: Record<string, string> = { Authorization: `Bearer ${init.bearer ?? "anon"}`, apikey: "anon" };
  if (init.ip) headers["x-test-ip"] = init.ip;
  if (init.token !== null) headers["x-admin-token"] = init.token ?? TOKEN;
  if (init.origin !== null) headers.Origin = init.origin ?? SITE;
  if (init.body !== undefined) headers["Content-Type"] = "application/json";
  return new Request(`https://example.supabase.co/functions/v1/admin${path}`, {
    method: init.method ?? (init.body === undefined ? "GET" : "POST"),
    headers,
    body: init.body === undefined ? undefined : typeof init.body === "string" ? init.body : JSON.stringify(init.body),
  });
}

/** Every answer: no caching, and CORS only for the site. */
function assertHeaders(response: Response, origin: string | null = SITE) {
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), allowedOrigin(origin) ? origin : null);
  assert.notEqual(response.headers.get("Access-Control-Allow-Origin"), "*");
}

async function errorCode(response: Response): Promise<string> {
  const body = await response.json();
  assert.equal(typeof body.error.message, "string");
  return body.error.code;
}

// MARK: - Token

Deno.test("constantTimeEqual compares length and every byte", () => {
  assert.ok(constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 3])));
  assert.ok(!constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 4])));
  assert.ok(!constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2])));
  assert.ok(!constantTimeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2, 0])));
  assert.ok(!constantTimeEqual(new Uint8Array([0]), new Uint8Array([])));
  assert.ok(constantTimeEqual(new Uint8Array([]), new Uint8Array([])));
});

Deno.test("the secret must be 64 hex characters; the token's SHA-256 must match it", async () => {
  assert.equal(parseDigest(undefined), undefined);
  assert.equal(parseDigest(""), undefined);
  assert.equal(parseDigest(TOKEN), undefined, "never the token itself");
  assert.equal(parseDigest(TOKEN_SHA256.slice(1)), undefined);
  assert.equal(parseDigest(TOKEN_SHA256.replace(/.$/, "g")), undefined);
  const expected = parseDigest(` ${TOKEN_SHA256.toUpperCase()}\n`)!;
  assert.equal(expected.length, 32);
  assert.ok(await tokenMatches(TOKEN, expected));
  assert.ok(!(await tokenMatches(TOKEN + "x", expected)));
  assert.ok(!(await tokenMatches(TOKEN.slice(0, -1), expected)));
  assert.ok(!(await tokenMatches(TOKEN_SHA256, expected)), "the digest isn't the token");
  assert.ok(!(await tokenMatches("", parseDigest(await sha256Hex(""))!)), "an empty token never matches");
  assert.ok(!(await tokenMatches(null, expected)));
});

Deno.test("without ADMIN_TOKEN_SHA256 or ADMIN_EMAILS every call is a 503 admin_disabled, before anything", async () => {
  const envs: Record<string, string>[] = [
    {},
    { ADMIN_TOKEN_SHA256: "" },
    { ADMIN_TOKEN_SHA256: "not-hex" },
    { ADMIN_TOKEN_SHA256: "not-hex", ADMIN_EMAILS: " , " },
  ];
  for (const env of envs) {
    const { deps, calls, authCalls } = fake({ env });
    for (const init of [{}, { token: null, bearer: ownerJwt() }]) {
      const response = await handleAdmin(request("/overview", init), deps);
      assert.equal(response.status, 503);
      assert.equal(await errorCode(response), "admin_disabled");
      assertHeaders(response);
    }
    assert.equal(calls.length, 0);
    assert.equal(authCalls.length, 0);
  }
});

Deno.test("a missing or wrong token is a 401, counted by the gate", async () => {
  const { deps, calls } = fake();
  for (const token of [null, "", "wrong", TOKEN + "x", TOKEN_SHA256]) {
    const response = await handleAdmin(request("/overview", { token }), deps);
    assert.equal(response.status, 401, `token ${token}`);
    assert.equal(await errorCode(response), "unauthorized");
    assertHeaders(response);
  }
  assert.deepEqual(calls.map((c) => [c.fn, c.args?.p_token_ok, c.args?.p_ip]), [
    ["admin_gate", false, IP],
    ["admin_gate", false, IP],
    ["admin_gate", false, IP],
    ["admin_gate", false, IP],
    ["admin_gate", false, IP],
  ]);
});

Deno.test("five misses lock the address out, even for the right token; others go on", async () => {
  const { deps, calls } = fake();
  for (let i = 0; i < 5; i++) {
    assert.equal((await handleAdmin(request("/overview", { token: `guess-${i}` }), deps)).status, 401);
  }
  const locked = await handleAdmin(request("/overview"), deps);
  assert.equal(locked.status, 429);
  assert.equal(locked.headers.get("Retry-After"), "900");
  const body = await locked.json();
  assert.equal(body.error.code, "locked_out");
  assert.equal(body.error.retry_after, 900);
  assertHeaders(locked);
  assert.ok(!calls.some((c) => c.fn.startsWith("ops_")), "nothing was read");

  assert.equal((await handleAdmin(request("/audit", { ip: "198.51.100.9" }), deps)).status, 200, "another address");
  assert.equal((await handleAdmin(request("/audit"), deps)).status, 429, "still locked");
});

Deno.test("past 60 requests a minute: 429 rate_limited", async () => {
  const { deps } = fake();
  for (let i = 0; i < 60; i++) assert.equal((await handleAdmin(request("/audit"), deps)).status, 200);
  const response = await handleAdmin(request("/audit"), deps);
  assert.equal(response.status, 429);
  assert.equal(await errorCode(response), "rate_limited");
  assert.equal(response.headers.get("Retry-After"), "30");
});

Deno.test("when the gate can't be asked, everything is refused (fails closed)", async () => {
  const { deps, calls } = fake({ fail: ["admin_gate"] });
  const response = await handleAdmin(request("/overview"), deps);
  assert.equal(response.status, 503);
  assert.equal(await errorCode(response), "unavailable");
  assert.deepEqual(calls.map((c) => c.fn), ["admin_gate"]);
});

// MARK: - The owner's session

Deno.test("ADMIN_EMAILS is comma-separated, trimmed and read in any case", () => {
  assert.deepEqual([...parseAdminEmails(SESSION_ENV.ADMIN_EMAILS)], [OWNER_EMAIL, "someone.else@example.com"]);
  assert.equal(parseAdminEmails(undefined).size, 0);
  assert.equal(parseAdminEmails(" , ").size, 0);
});

Deno.test("jwtClaims reads a JWT's payload and refuses anything else", () => {
  assert.equal(jwtClaims(ownerJwt())?.email, OWNER_EMAIL);
  assert.equal(jwtClaims(ANON_KEY)?.role, "anon");
  const notJwts = [
    "",
    "anon",
    "a.b",
    "a.b.c.d",
    "a.!!.c",
    `a.${base64url("[1]")}.c`,
    `a.${base64url("not json")}.c`,
    `a.${"x".repeat(9000)}.c`,
  ];
  for (const value of notJwts) assert.equal(jwtClaims(value), null, value.slice(0, 40));
});

Deno.test("isAdminUser: an admin email, confirmed, an email-provider account, not anonymous", () => {
  const admins = parseAdminEmails(SESSION_ENV.ADMIN_EMAILS);
  assert.ok(isAdminUser(ownerUser(), admins));
  assert.ok(isAdminUser(ownerUser({ email: " INFO@nextgenlab.com.tr" }), admins));
  assert.ok(isAdminUser(ownerUser({ app_metadata: { provider: "apple", providers: ["apple", "email"] } }), admins));
  const refused = [
    ownerUser({ email: "girl@example.com" }),
    ownerUser({ email: null }),
    ownerUser({ email_confirmed_at: null }),
    ownerUser({ email_confirmed_at: undefined }),
    ownerUser({ email_confirmed_at: "" }),
    ownerUser({ is_anonymous: true }),
    ownerUser({ app_metadata: { provider: "apple", providers: ["apple"] } }),
    ownerUser({ app_metadata: undefined }),
  ];
  for (const user of refused) assert.ok(!isAdminUser(user, admins), JSON.stringify(user));
  assert.ok(!isAdminUser(ownerUser(), new Set()), "nobody without ADMIN_EMAILS");
});

Deno.test("the owner's session admits, checked once with the auth server, and the gate counts it as right", async () => {
  const token = ownerJwt();
  for (const env of [SESSION_ENV, { ...SESSION_ENV, ADMIN_TOKEN_SHA256: TOKEN_SHA256 }]) {
    const { deps, calls, authCalls } = fake({
      env,
      users: { [token]: ownerUser() },
      data: { admin_audit_recent: [], admin_action: { ok: true, result: { outcome: "done" } } },
    });
    const audit = await handleAdmin(request("/audit", { token: null, bearer: token }), deps);
    assert.equal(audit.status, 200);
    assertHeaders(audit);
    assert.deepEqual(await audit.json(), { entries: [] });
    const action = await handleAdmin(
      request("/action", { token: null, bearer: token, body: { action: "pause_ai" } }),
      deps,
    );
    assert.equal(action.status, 200);
    assert.deepEqual(await action.json(), { ok: true, result: { outcome: "done" } });
    assert.deepEqual(authCalls, [token, token]);
    assert.deepEqual(calls.map((c) => [c.fn, c.args?.p_token_ok]), [
      ["admin_gate", true],
      ["admin_audit_recent", undefined],
      ["admin_gate", true],
      ["admin_action", undefined],
    ]);
  }
});

Deno.test("someone else's session is a 403 forbidden from its claims alone, counted as a miss", async () => {
  const sessions = [
    ownerJwt({ sub: USER_ID, email: "girl@example.com" }),
    ownerJwt({ email: undefined }),
    // Anonymous app users, even with the owner's email in the token.
    jwt({ sub: USER_ID, role: "authenticated", is_anonymous: true, exp: NOW_SECONDS + 3600, amr: [] }),
    ownerJwt({ is_anonymous: true }),
    // Opened another way than the email provider's password.
    ownerJwt({ amr: [{ method: "oauth", timestamp: NOW_SECONDS }] }),
    ownerJwt({ amr: [{ method: "otp", timestamp: NOW_SECONDS }] }),
    ownerJwt({ amr: undefined }),
  ];
  for (const token of sessions) {
    const { deps, calls, authCalls } = fake({ env: SESSION_ENV, users: { [token]: ownerUser() } });
    const response = await handleAdmin(request("/overview", { token: null, bearer: token }), deps);
    assert.equal(response.status, 403, JSON.stringify(jwtClaims(token)));
    assert.equal(await errorCode(response), "forbidden");
    assertHeaders(response);
    assert.deepEqual(authCalls, [], "refused without asking the auth server");
    assert.deepEqual(calls.map((c) => [c.fn, c.args?.p_token_ok]), [["admin_gate", false]]);
  }
});

Deno.test("a session whose user the auth server doesn't back up is a 403: unconfirmed, another provider…", async () => {
  const users = [
    ownerUser({ email_confirmed_at: null }),
    ownerUser({ app_metadata: { provider: "apple", providers: ["apple"] } }),
    ownerUser({ email: "girl@example.com" }),
    ownerUser({ is_anonymous: true }),
  ];
  for (const user of users) {
    const token = ownerJwt();
    const { deps, calls, authCalls } = fake({ env: SESSION_ENV, users: { [token]: user } });
    const response = await handleAdmin(request("/overview", { token: null, bearer: token }), deps);
    assert.equal(response.status, 403, JSON.stringify(user));
    assert.equal(await errorCode(response), "forbidden");
    assert.deepEqual(authCalls, [token]);
    assert.deepEqual(calls.map((c) => [c.fn, c.args?.p_token_ok]), [["admin_gate", false]]);
  }
});

Deno.test("an expired, ended or mismatched session is a 401 session_expired, counted as a miss", async () => {
  const expired = ownerJwt({ exp: NOW_SECONDS });
  const noExpiry = ownerJwt({ exp: undefined });
  const noSubject = ownerJwt({ sub: "" });
  const signedOut = ownerJwt({ session_id: "signed-out" });
  const someoneElse = ownerJwt({ session_id: "another-user" });
  const { deps, calls, authCalls } = fake({
    env: SESSION_ENV,
    users: { [signedOut]: null, [someoneElse]: ownerUser({ id: USER_ID }) },
  });
  for (const token of [expired, noExpiry, noSubject, signedOut, someoneElse]) {
    const response = await handleAdmin(request("/overview", { token: null, bearer: token }), deps);
    assert.equal(response.status, 401, JSON.stringify(jwtClaims(token)));
    assert.equal(await errorCode(response), "session_expired");
    assertHeaders(response);
  }
  assert.deepEqual(authCalls, [signedOut, someoneElse], "expired tokens are refused from their claims");
  assert.deepEqual(calls.map((c) => [c.fn, c.args?.p_token_ok]), Array(5).fill(["admin_gate", false]));
});

Deno.test("a bearer that isn't a session (anon key, service role, garbage) leaves the token in charge", async () => {
  const serviceRole = jwt({ role: "service_role", iss: "supabase", exp: NOW_SECONDS + 3600 });
  for (const bearer of [ANON_KEY, serviceRole, "anon", "a.b.c"]) {
    const { deps, authCalls } = fake({ env: { ...SESSION_ENV, ADMIN_TOKEN_SHA256: TOKEN_SHA256 } });
    const missing = await handleAdmin(request("/audit", { token: null, bearer }), deps);
    assert.equal(missing.status, 401, bearer.slice(0, 20));
    assert.equal(await errorCode(missing), "unauthorized");
    assert.equal((await handleAdmin(request("/audit", { bearer }), deps)).status, 200);
    assert.deepEqual(authCalls, []);
  }
});

Deno.test("the right token admits without the auth server, whatever the bearer; alone, ADMIN_EMAILS takes no token", async () => {
  const both = fake({ env: { ...SESSION_ENV, ADMIN_TOKEN_SHA256: TOKEN_SHA256 } });
  assert.equal(
    (await handleAdmin(request("/audit", { bearer: ownerJwt({ email: "girl@example.com" }) }), both.deps)).status,
    200,
  );
  assert.equal((await handleAdmin(request("/audit", { bearer: ownerJwt({ exp: 1 }) }), both.deps)).status, 200);
  assert.deepEqual(both.authCalls, []);

  const { deps, calls } = fake({ env: SESSION_ENV });
  const response = await handleAdmin(request("/audit"), deps);
  assert.equal(response.status, 401);
  assert.equal(await errorCode(response), "unauthorized");
  assert.deepEqual(calls.map((c) => [c.fn, c.args?.p_token_ok]), [["admin_gate", false]]);
});

Deno.test("when the auth server can't answer: 503 unavailable, nothing counted or read", async () => {
  const token = ownerJwt();
  const { deps, calls } = fake({ env: SESSION_ENV, users: { [token]: "down" } });
  const response = await handleAdmin(request("/overview", { token: null, bearer: token }), deps);
  assert.equal(response.status, 503);
  assert.equal(await errorCode(response), "unavailable");
  assert.equal(response.headers.get("Retry-After"), "30");
  assert.equal(calls.length, 0);
});

Deno.test("refused sessions lock the address like wrong tokens; the owner's session forgives earlier misses", async () => {
  const token = ownerJwt();
  const other = ownerJwt({ sub: USER_ID, email: "girl@example.com" });
  const { deps } = fake({ env: SESSION_ENV, users: { [token]: ownerUser() } });
  const send = async (bearer: string, ip?: string) =>
    (await handleAdmin(request("/overview", { token: null, bearer, ip }), deps)).status;
  for (let i = 0; i < 4; i++) assert.equal(await send(other), 403);
  assert.equal(await send(token), 200, "four misses, then the owner: forgiven");
  for (let i = 0; i < 5; i++) assert.equal(await send(other), 403);
  const locked = await handleAdmin(request("/overview", { token: null, bearer: token }), deps);
  assert.equal(locked.status, 429);
  assert.equal(await errorCode(locked), "locked_out");
  assert.equal(locked.headers.get("Retry-After"), "900");
  assert.equal(await send(token, "198.51.100.9"), 200, "another address");
});

Deno.test("logs never carry the session, its email or its user", async () => {
  const token = ownerJwt();
  const other = ownerJwt({ sub: USER_ID, email: "girl@example.com" });
  const { deps, logs } = fake({ env: SESSION_ENV, users: { [token]: ownerUser() } });
  for (const bearer of [token, other, ownerJwt({ exp: NOW_SECONDS - 60 })]) {
    await handleAdmin(request("/overview", { token: null, bearer }), deps);
  }
  assert.deepEqual(logs.map((entry) => entry.outcome).filter((o) => !String(o).startsWith("section_")), [
    "ok",
    "forbidden",
    "session_expired",
  ]);
  const logged = JSON.stringify(logs);
  for (const secret of [token, other, OWNER_EMAIL, "girl@example.com", OWNER_ID, USER_ID, "nextgenlab"]) {
    assert.ok(!logged.includes(secret), `logged ${secret}`);
  }
});

// MARK: - CORS

Deno.test("CORS: only aybuke.org, www.aybuke.org and localhost", async () => {
  for (const origin of ["https://aybuke.org", "https://www.aybuke.org", "http://localhost", "http://localhost:5173"]) {
    assert.ok(allowedOrigin(origin), origin);
    const { deps } = fake();
    const response = await handleAdmin(request("/audit", { origin }), deps);
    assert.equal(response.status, 200);
    assertHeaders(response, origin);
    assert.equal(response.headers.get("Vary"), "Origin");
  }
  for (
    const origin of [
      "http://aybuke.org",
      "https://evil.aybuke.org",
      "https://aybuke.org.evil.com",
      "https://aybuke.org:8443",
      "http://localhost.evil.com",
      "https://localhost:3000",
      "http://127.0.0.1:5173",
      "null",
    ]
  ) {
    assert.ok(!allowedOrigin(origin), origin);
    const { deps, calls } = fake();
    const response = await handleAdmin(request("/overview", { origin }), deps);
    assert.equal(response.status, 403, origin);
    assert.equal(await errorCode(response), "origin_not_allowed");
    assertHeaders(response, origin);
    assert.equal(calls.length, 0, "refused before the database");
  }
});

Deno.test("CORS preflight: the admin header allowed, nothing read", async () => {
  const { deps, calls } = fake();
  const response = await handleAdmin(request("/action", { method: "OPTIONS", token: null }), deps);
  assert.equal(response.status, 204);
  assertHeaders(response);
  assert.match(response.headers.get("Access-Control-Allow-Headers") ?? "", /x-admin-token/);
  assert.match(response.headers.get("Access-Control-Allow-Headers") ?? "", /apikey/);
  assert.equal(response.headers.get("Access-Control-Allow-Methods"), "GET, POST, OPTIONS");
  assert.equal(calls.length, 0);

  const refused = await handleAdmin(request("/action", { method: "OPTIONS", origin: "https://evil.example" }), deps);
  assert.equal(refused.status, 403);
  assert.equal(refused.headers.get("Access-Control-Allow-Origin"), null);
});

Deno.test("a request without an Origin (curl) still needs the token", async () => {
  const { deps } = fake();
  assert.equal((await handleAdmin(request("/audit", { origin: null, token: null }), deps)).status, 401);
  const response = await handleAdmin(request("/audit", { origin: null }), deps);
  assert.equal(response.status, 200);
  assertHeaders(response, null);
});

// MARK: - Routes

const DAILY = {
  day: "2026-10-17",
  jobs: { total: 57, completed: 50, users: 12 },
  breakers: { all_jobs: 57, all_jobs_cap: 400, switches: {} },
  top_installs: [{ install: INSTALL_KEY.slice(0, 12), jobs: 9 }, { install: "not-hex!", jobs: 1 }],
  top_ips: [{ ip: "abcdef012345", requests: 30 }],
};

Deno.test("GET /admin/overview: every summary, with tags for the top installs and addresses", async () => {
  const { deps, calls } = fake({
    data: {
      ops_daily_summary: DAILY,
      ops_members_summary: { members: { total: 321 }, pro: { active_members: 8 } },
      ops_provider_budget: { provider: "xai", remaining_cents: 978 },
      ops_polls_summary: { created: 3, live_now: 2 },
      admin_ai_state: { paused: true, scope: "all", reason: "admin_page", until: "2026-10-18T09:30:00+00:00" },
    },
  });
  const response = await handleAdmin(request("/overview"), deps);
  assert.equal(response.status, 200);
  assertHeaders(response);
  const body = await response.json();
  assert.deepEqual(Object.keys(body).sort(), ["ai", "budget", "generated_at", "members", "polls", "today"]);
  assert.equal(body.generated_at, NOW.toISOString());
  assert.deepEqual(body.today.top_installs, [{ tag: `i-${INSTALL_KEY.slice(0, 12)}`, jobs: 9 }]);
  assert.deepEqual(body.today.top_ips, [{ tag: "a-abcdef012345", requests: 30 }]);
  assert.equal(body.today.jobs.total, 57);
  assert.equal(body.members.members.total, 321);
  assert.equal(body.budget.remaining_cents, 978);
  assert.equal(body.polls.live_now, 2);
  assert.deepEqual(body.ai, { paused: true, scope: "all", reason: "admin_page", until: "2026-10-18T09:30:00+00:00" });
  assert.deepEqual(calls.slice(1).map((c) => [c.fn, c.args]), [
    ["ops_daily_summary", { p_day: "2026-10-17" }],
    ["ops_members_summary", undefined],
    ["ops_provider_budget", { p_provider: "xai" }],
    ["ops_polls_summary", { p_day: "2026-10-17" }],
    ["admin_ai_state", undefined],
  ]);
});

Deno.test("GET /admin/overview: a section that can't be read is null; the rest still shows", async () => {
  const { deps, logs } = fake({ data: { ops_daily_summary: DAILY }, fail: ["ops_members_summary"] });
  const body = await (await handleAdmin(request("/overview"), deps)).json();
  assert.equal(body.members, null);
  assert.equal(body.today.jobs.total, 57);
  assert.ok(logs.some((entry) => entry.outcome === "section_unavailable:ops_members_summary"));
  assert.ok(!JSON.stringify(logs).includes(USER_ID), "the database's message isn't logged");
});

Deno.test("GET /admin/moderation: the three lists, tags kept, raw ids dropped", async () => {
  const { deps, calls } = fake({
    data: {
      admin_moderation: {
        poll_reports: [{
          poll_id: "Ab3_Xy9-Kq2LmN0p",
          reports: 3,
          reasons: ["bullying"],
          user: "u-0123456789ab",
          install: "i-ba9876543210",
          user_id: USER_ID,
        }],
        reports: [{ reason: "offensive", details: `mail me at girl@example.com, I'm ${IP}`, user: "u-0123456789ab" }],
        strikes: [{ install: "i-ba9876543210", users: ["u-0123456789ab"], strikes: 4, install_key: INSTALL_KEY }],
        extra: "dropped",
      },
    },
  });
  const response = await handleAdmin(request("/moderation"), deps);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.deepEqual(Object.keys(body).sort(), ["poll_reports", "reports", "strikes"]);
  assert.deepEqual(body.poll_reports[0], {
    poll_id: "Ab3_Xy9-Kq2LmN0p",
    reports: 3,
    reasons: ["bullying"],
    user: "u-0123456789ab",
    install: "i-ba9876543210",
  });
  assert.equal(body.reports[0].details, "mail me at [email], I'm [address]");
  assert.deepEqual(body.strikes[0], { install: "i-ba9876543210", users: ["u-0123456789ab"], strikes: 4 });
  assert.deepEqual(calls[1], { fn: "admin_moderation", args: { p_days: 7 } });
});

Deno.test("GET /admin/audit: the last 50 entries", async () => {
  const entries = [{
    at: "2026-10-17T09:00:00+00:00",
    action: "block",
    target: "i-ba9876543210",
    address: "a-0123456789ab",
    outcome: "done",
  }];
  const { deps, calls } = fake({ data: { admin_audit_recent: entries } });
  const response = await handleAdmin(request("/audit"), deps);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { entries });
  assert.deepEqual(calls[1], { fn: "admin_audit_recent", args: { p_limit: 50 } });
});

Deno.test("POST /admin/action: each action goes to admin_action with the caller's address", async () => {
  const cases: [Record<string, unknown>, string | null][] = [
    [{ action: "pause_ai" }, null],
    [{ action: "pause_ai", target: "free" }, "free"],
    [{ action: "resume_ai", target: null }, null],
    [{ action: "resume_ai", target: "all" }, "all"],
    [{ action: "take_down_poll", target: "Ab3_Xy9-Kq2LmN0p" }, "Ab3_Xy9-Kq2LmN0p"],
    [{ action: "restore_poll", target: "Ab3_Xy9-Kq2LmN0p" }, "Ab3_Xy9-Kq2LmN0p"],
    [{ action: "block", target: "i-ba9876543210" }, "i-ba9876543210"],
    [{ action: "unblock", target: "u-0123456789ab" }, "u-0123456789ab"],
  ];
  for (const [body, target] of cases) {
    const { deps, calls } = fake({
      data: { admin_action: { ok: true, result: { outcome: "done", user_id: USER_ID, install_key: INSTALL_KEY } } },
    });
    const response = await handleAdmin(request("/action", { body }), deps);
    assert.equal(response.status, 200, JSON.stringify(body));
    assertHeaders(response);
    assert.deepEqual(await response.json(), { ok: true, result: { outcome: "done" } });
    assert.deepEqual(calls[1], { fn: "admin_action", args: { p_action: body.action, p_target: target, p_ip: IP } });
  }
});

Deno.test("POST /admin/action: the database's refusals keep their status", async () => {
  for (const [code, status] of [["not_found", 404], ["ambiguous", 409], ["bad_request", 400]] as const) {
    const { deps } = fake({ data: { admin_action: { ok: false, code, status } } });
    const response = await handleAdmin(
      request("/action", { body: { action: "block", target: "i-000000000000" } }),
      deps,
    );
    assert.equal(response.status, status);
    assert.equal(await errorCode(response), code);
  }
  const { deps } = fake({ fail: ["admin_action"] });
  const response = await handleAdmin(request("/action", { body: { action: "pause_ai" } }), deps);
  assert.equal(response.status, 500);
  assert.equal(await errorCode(response), "internal");
});

Deno.test("POST /admin/action: anything else is a 400 before the database", async () => {
  const bad: unknown[] = [
    "not json",
    "[]",
    "null",
    "42",
    {},
    { action: "nuke" },
    { action: "PAUSE_AI" },
    { action: "pause_ai", target: "everything" },
    { action: "pause_ai", target: 1 },
    { action: "pause_ai", hours: 48 },
    { action: "resume_ai", target: "" },
    { action: "take_down_poll" },
    { action: "take_down_poll", target: "short" },
    { action: "take_down_poll", target: "Ab3_Xy9-Kq2LmN0p!" },
    { action: "restore_poll", target: "Ab3/Xy9+Kq2LmN0p" },
    { action: "block" },
    { action: "block", target: INSTALL_KEY },
    { action: "block", target: USER_ID },
    { action: "block", target: "i-BA9876543210" },
    { action: "block", target: "a-0123456789ab" },
    { action: "unblock", target: "u-0123456789abc" },
    { action: "block", target: ["i-ba9876543210"] },
    JSON.stringify({ action: "pause_ai", target: "x".repeat(2000) }),
  ];
  for (const body of bad) {
    const { deps, calls } = fake();
    const response = await handleAdmin(request("/action", { method: "POST", body }), deps);
    assert.equal(response.status, 400, JSON.stringify(body).slice(0, 80));
    assert.equal(await errorCode(response), "bad_request");
    assert.deepEqual(calls.map((c) => c.fn), ["admin_gate"], "admin_action is never called");
  }
  assert.throws(() => parseAction({ action: "block", target: "i-ba9876543210", extra: true }));
  assert.deepEqual(parseAction({ action: "block", target: "i-ba9876543210" }), {
    action: "block",
    target: "i-ba9876543210",
  });
});

Deno.test("unknown routes are 404 and wrong methods 405, both only after the token", async () => {
  const { deps } = fake();
  assert.equal((await handleAdmin(request("/users", { token: null }), deps)).status, 401);
  assert.equal((await handleAdmin(request("/users"), deps)).status, 404);
  assert.equal((await handleAdmin(request(""), deps)).status, 404);
  assert.equal((await handleAdmin(request("/constructor"), deps)).status, 404, "no inherited routes");
  const wrong = await handleAdmin(request("/overview", { body: {} }), deps);
  assert.equal(wrong.status, 405);
  assert.equal(await errorCode(wrong), "method_not_allowed");
  assert.equal((await handleAdmin(request("/action"), deps)).status, 405);
  assert.equal(routeOf(new URL("https://x.supabase.co/functions/v1/admin/overview/")), "overview");
  assert.equal(routeOf(new URL("https://x.supabase.co/admin/audit")), "audit");
});

// MARK: - No PII

Deno.test("no ids, keys, addresses or emails in any answer, and none in the logs", async () => {
  const leaky = {
    ops_daily_summary: { ...DAILY, note: `user ${USER_ID} from ${IP} or 2001:db8:0:0::/64`, key: INSTALL_KEY },
    ops_members_summary: { at: "2026-10-17T09:30:00+00:00", ids: [USER_ID], email: "owner@example.com" },
    ops_provider_budget: { provider: "xai", as_of: "2026-10-15T10:15:30.123+00:00" },
    admin_ai_state: { paused: true, reason: "contact owner@example.com" },
    admin_moderation: {
      poll_reports: [{ poll_id: "Ab3_Xy9-Kq2LmN0p", user_id: USER_ID, install_key: INSTALL_KEY }],
      reports: [{ details: `${USER_ID} ${INSTALL_KEY} ${IP}`, job_id: USER_ID }],
      strikes: [{ user_ids: [USER_ID], ip_key: INSTALL_KEY }],
    },
    admin_audit_recent: [{ action: "block", target: "i-ba9876543210", address: IP }],
  };
  const { deps, logs } = fake({ data: leaky });
  const answers: string[] = [];
  for (const path of ["/overview", "/moderation", "/audit"]) {
    const response = await handleAdmin(request(path), deps);
    assert.equal(response.status, 200, path);
    answers.push(await response.text());
  }
  const text = answers.join("\n");
  for (const secret of [USER_ID, INSTALL_KEY, IP, "owner@example.com", "2001:db8", TOKEN, TOKEN_SHA256]) {
    assert.ok(!text.includes(secret), `leaked ${secret}`);
  }
  assert.ok(text.includes("Ab3_Xy9-Kq2LmN0p"), "poll ids stay: the page acts on them");
  assert.ok(text.includes("2026-10-15T10:15:30.123+00:00"), "times aren't mistaken for addresses");
  assert.ok(text.includes("i-ba9876543210"), "tags stay");

  const logged = JSON.stringify(logs);
  for (const secret of [USER_ID, INSTALL_KEY, IP, TOKEN, TOKEN_SHA256, "Ab3_Xy9"]) {
    assert.ok(!logged.includes(secret), `logged ${secret}`);
  }
  for (const entry of logs) {
    assert.deepEqual(Object.keys(entry).sort(), ["fn", "ms", "outcome", "route", "status"]);
  }
});

Deno.test("redact and scrub", () => {
  assert.equal(redact(`a ${USER_ID.toUpperCase()} b`), "a [id] b");
  assert.equal(redact(`key ${INSTALL_KEY}`), "key [key]");
  assert.equal(redact("from 10.0.0.1 and fe80:0:0:0:1::/64"), "from [address] and [address]");
  assert.equal(redact("write to a.b+c@mail.example.org!"), "write to [email]!");
  assert.equal(redact("u-0123456789ab at 2026-10-17T09:30:00Z"), "u-0123456789ab at 2026-10-17T09:30:00Z");
  assert.deepEqual(scrub({ user_id: "x", nested: [{ install_key: "y", ok: 1 }], n: 2, flag: false, none: null }), {
    nested: [{ ok: 1 }],
    n: 2,
    flag: false,
    none: null,
  });
});
