// deno test ad-reward/
// The routes and the contract (handler.ts) with a stubbed database and
// session, and AdMob's callback signed with a local P-256 key standing in for
// Google's. What each database call does is tested in
// backend/supabase/tests/ad_rewards_test.sql (credits) and
// rewarded_unlocks_test.sql (Pro tries); Google's signature check in
// _shared/admob_test.ts.
import assert from "node:assert/strict";
import catalog from "../_shared/catalog.json" with { type: "json" };
import { base64UrlEncode, rawToDer, VerifierKeys, verifyCallback } from "../_shared/admob.ts";
import { HttpError } from "../_shared/http.ts";
import { type AdRewardDeps, handleAdReward, type RpcResult } from "./handler.ts";

const USER = "8b6f2a52-0f43-4c43-9a51-6a7c9bd40c11";
const TOKEN = "3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b";
const PRO_LOOK = catalog.templates.find((template) => template.isPro)!.id;
const FREE_LOOK = catalog.templates.find((template) => !template.isPro)!.id;
const PRO_STYLE = catalog.proStyles[0];
const POLICY = [{ daily_cap: 2, credits: 1, token_ttl: "00:30:00", unlock_daily_cap: 1, unlock_ttl: "00:30:00" }];
const AD_UNIT = "1406702504";
const URL_BASE = "https://example.supabase.co/functions/v1/ad-reward";
const EXPIRES = "2026-11-01T10:30:00+00:00";

type Answer = RpcResult | ((args: Record<string, unknown>) => RpcResult);

function stub(answers: Record<string, Answer>, options: { isPro?: boolean; keys?: VerifierKeys } = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const deps: AdRewardDeps = {
    rpc: (fn, args = {}) => {
      calls.push({ fn, args });
      const answer = answers[fn] ?? (fn === "ad_reward_policy" ? { data: POLICY, error: null } : undefined);
      if (!answer) return Promise.resolve({ data: null, error: { message: `unexpected call ${fn}` } });
      return Promise.resolve(typeof answer === "function" ? answer(args) : answer);
    },
    requireUser: (req) =>
      req.headers.get("Authorization")
        ? Promise.resolve({ id: USER })
        : Promise.reject(new HttpError(401, "unauthorized", "Missing session.")),
    isPro: () => Promise.resolve(options.isPro ?? false),
    verifyInstall: () => Promise.resolve({ status: "verified", appTransactionId: "atid-1", environment: "Sandbox" }),
    verifyCallback: (rawQuery) =>
      verifyCallback(rawQuery, options.keys ?? new VerifierKeys(() => Promise.reject(new Error("no keys")))),
    env: { get: (name) => name === "ADMOB_REWARDED_AD_UNIT" ? `ca-app-pub-2292230772061554/${AD_UNIT}` : undefined },
  };
  return { deps, calls, fns: () => calls.map((call) => call.fn) };
}

function appRequest(method: string, query = "", body?: unknown): Request {
  return new Request(URL_BASE + query, {
    method,
    headers: { Authorization: "Bearer session", "X-App-Transaction": "app-transaction-jws" },
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function send(deps: AdRewardDeps, req: Request) {
  const response = await handleAdReward(req, deps);
  return { status: response.status, body: await response.json() };
}

const INSTALL = { p_app_transaction_id: "atid-1", p_install_status: "verified", p_install_environment: "Sandbox" };
const issued = (remaining: number) => ({
  data: [{ reward_token: TOKEN, valid_until: EXPIRES, remaining_today: remaining }],
  error: null,
});

// MARK: - POST

Deno.test("create: no body (today's app), {} or kind credit is the credit ad, as before", async () => {
  for (const body of [undefined, {}, { kind: "credit" }, ""]) {
    const { deps, calls } = stub({ issue_ad_reward_token: issued(1) });
    const { status, body: answer } = await send(deps, appRequest("POST", "", body));
    assert.equal(status, 201, JSON.stringify(body));
    assert.deepEqual(answer, { token: TOKEN, kind: "credit", expires_at: EXPIRES, remaining_today: 1, daily_cap: 2 });
    assert.deepEqual(calls[0], { fn: "issue_ad_reward_token", args: { p_user: USER, p_is_pro: false, ...INSTALL } });
  }
});

Deno.test("create: a try names exactly one Pro look, and the token is for it", async () => {
  const { deps, calls } = stub({ issue_ad_unlock_token: issued(0) });
  const { status, body } = await send(deps, appRequest("POST", "", { kind: "unlock", template_id: PRO_LOOK }));
  assert.equal(status, 201);
  assert.deepEqual(body, {
    token: TOKEN,
    kind: "unlock",
    template_id: PRO_LOOK,
    expires_at: EXPIRES,
    remaining_today: 0,
    daily_cap: 1,
  });
  assert.deepEqual(calls[0], {
    fn: "issue_ad_unlock_token",
    args: { p_user: USER, p_is_pro: false, p_unlock_type: "template", p_unlock_id: PRO_LOOK, ...INSTALL },
  });
});

Deno.test("create: a try of a Pro Create style", async () => {
  const { deps, calls } = stub({ issue_ad_unlock_token: issued(0) });
  const { status, body } = await send(deps, appRequest("POST", "", { kind: "unlock", style_id: PRO_STYLE }));
  assert.equal(status, 201);
  assert.equal(body.style_id, PRO_STYLE);
  assert.equal(body.template_id, undefined);
  assert.equal(calls[0].args.p_unlock_type, "style");
  assert.equal(calls[0].args.p_unlock_id, PRO_STYLE);
});

Deno.test("create: anything but one Pro look or style is refused before an ad, without asking the database", async () => {
  const cases: [unknown, number, string][] = [
    [{ kind: "unlock", template_id: FREE_LOOK }, 400, "not_unlockable"],
    [{ kind: "unlock", template_id: "no-such-look" }, 400, "not_unlockable"],
    [{ kind: "unlock" }, 400, "bad_request"],
    [{ kind: "unlock", template_id: PRO_LOOK, style_id: PRO_STYLE }, 400, "bad_request"],
    [{ kind: "gold" }, 400, "bad_request"],
    ["{not json", 400, "bad_request"],
    [[{ kind: "unlock" }], 400, "bad_request"],
    [JSON.stringify({ kind: "unlock", template_id: PRO_LOOK, padding: "x".repeat(5000) }), 400, "bad_request"],
  ];
  for (const [body, status, code] of cases) {
    const { deps, fns } = stub({});
    const answer = await send(deps, appRequest("POST", "", body));
    assert.equal(answer.status, status, JSON.stringify(body).slice(0, 80));
    assert.equal(answer.body.error.code, code, JSON.stringify(body).slice(0, 80));
    assert.deepEqual(fns(), [], "no token asked for");
  }
});

Deno.test("create: the database's refusals of a try reach the app as codes", async () => {
  const cases: [string, number, string][] = [
    ["AD_NOT_ELIGIBLE", 403, "not_eligible"],
    ["AD_NO_INSTALL", 403, "not_eligible"],
    ["AD_AI_PAUSED", 503, "ai_paused"],
    ["AD_NO_CREDITS", 409, "no_credits"],
    ["AD_DAILY_CAP", 409, "daily_cap"],
    ["AD_BAD_UNLOCK", 400, "not_unlockable"],
    ["connection reset", 500, "internal"],
  ];
  for (const [message, status, code] of cases) {
    const { deps } = stub({ issue_ad_unlock_token: { data: null, error: { message } } });
    const answer = await send(deps, appRequest("POST", "", { kind: "unlock", template_id: PRO_LOOK }));
    assert.equal(answer.status, status, message);
    assert.equal(answer.body.error.code, code, message);
    assert.ok(answer.body.error.message.length > 0);
    if (code === "no_credits") assert.equal(answer.body.error.credits_remaining, 0);
  }
});

Deno.test("create: no session, no token", async () => {
  const { deps, fns } = stub({});
  const response = await handleAdReward(
    new Request(URL_BASE, { method: "POST", body: JSON.stringify({ kind: "unlock", template_id: PRO_LOOK }) }),
    deps,
  );
  assert.equal(response.status, 401);
  assert.deepEqual(fns(), []);
});

// MARK: - AdMob's callback

async function signedCallback(token: string, transactionId: string) {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  const keys = new VerifierKeys(() =>
    Promise.resolve({ keys: [{ keyId: 7, pem: "unused", base64: btoa(String.fromCharCode(...spki)) }] })
  );
  const content = `ad_network=5450213213286189855&ad_unit=${AD_UNIT}&custom_data=${token}` +
    `&reward_amount=1&reward_item=credit&timestamp=1793520000000&transaction_id=${transactionId}`;
  const raw = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, new TextEncoder().encode(content)),
  );
  const signature = base64UrlEncode(rawToDer(raw));
  return { keys, content, url: `${URL_BASE}?${content}&signature=${signature}&key_id=7` };
}

Deno.test("grant: AdMob's signed callback redeems the try's token; the token decides what it pays", async () => {
  const { keys, url } = await signedCallback(TOKEN, "tx-unlock-1");
  const { deps, calls } = stub({
    redeem_ad_reward: { data: [{ outcome: "granted", credits_remaining: 2 }], error: null },
  }, { keys });
  // AdMob sends no session: the signature is the authentication.
  const { status, body } = await send(deps, new Request(url));
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true, outcome: "granted" });
  assert.deepEqual(calls, [{
    fn: "redeem_ad_reward",
    args: {
      p_transaction_id: "tx-unlock-1",
      p_token: TOKEN,
      p_ad_unit: AD_UNIT,
      p_reward_amount: 1,
      p_reward_item: "credit",
    },
  }]);
});

Deno.test("grant: a callback Google didn't sign grants nothing", async () => {
  const google = await signedCallback(TOKEN, "tx-unlock-2");
  const forged = await signedCallback(TOKEN, "tx-unlock-2");
  const { deps, fns } = stub({}, { keys: google.keys });
  const { status } = await send(deps, new Request(forged.url));
  assert.equal(status, 403);
  assert.deepEqual(fns(), []);
});

Deno.test("grant: a database error asks AdMob to try again", async () => {
  const { keys, url } = await signedCallback(TOKEN, "tx-unlock-3");
  const { deps } = stub({ redeem_ad_reward: { data: null, error: { message: "deadlock" } } }, { keys });
  assert.equal((await send(deps, new Request(url))).status, 500);
});

// MARK: - Poll

const statusRow = (row: Record<string, unknown>) => ({
  data: [{ remaining_today: 0, credits_remaining: 1, ...row }],
  error: null,
});

Deno.test("poll: a try is pending, then granted with its look and when it ends", async () => {
  const pending = stub({
    ad_reward_status: statusRow({
      outcome: "pending",
      reward_kind: "unlock",
      unlock_type: "template",
      unlock_id: PRO_LOOK,
      unlock_expires_at: null,
    }),
  });
  const before = await send(pending.deps, appRequest("GET", `?token=${TOKEN}`));
  assert.deepEqual(before.body, {
    token: TOKEN,
    kind: "unlock",
    status: "pending",
    template_id: PRO_LOOK,
    remaining_today: 0,
    daily_cap: 1,
    credits_remaining: 1,
  });
  assert.deepEqual(pending.calls.find((call) => call.fn === "ad_reward_status")?.args, {
    p_user: USER,
    p_token: TOKEN,
  });

  const granted = stub({
    ad_reward_status: statusRow({
      outcome: "granted",
      reward_kind: "unlock",
      unlock_type: "style",
      unlock_id: PRO_STYLE,
      unlock_expires_at: "2026-11-01T11:00:00+00:00",
    }),
  });
  const after = await send(granted.deps, appRequest("GET", `?token=${TOKEN}`));
  assert.equal(after.status, 200);
  assert.equal(after.body.status, "granted");
  assert.equal(after.body.kind, "unlock");
  assert.equal(after.body.style_id, PRO_STYLE);
  assert.equal(after.body.expires_at, "2026-11-01T11:00:00+00:00");
});

Deno.test("poll: a credit's token answers as before, and so does an answer from before the tries", async () => {
  for (const kind of ["credit", undefined]) {
    const { deps } = stub({
      ad_reward_status: statusRow({ outcome: "granted", remaining_today: 1, reward_kind: kind }),
    });
    const { body } = await send(deps, appRequest("GET", `?token=${TOKEN}`));
    assert.deepEqual(body, {
      token: TOKEN,
      kind: "credit",
      status: "granted",
      remaining_today: 1,
      daily_cap: 2,
      credits_remaining: 1,
    });
  }
  const { deps, fns } = stub({});
  const unknown = await send(deps, appRequest("GET", "?token=not-a-token"));
  assert.equal(unknown.body.status, "unknown");
  assert.ok(!fns().includes("ad_reward_status"));
});

Deno.test("poll: today's overview carries the tries", async () => {
  const overview = {
    remaining_today: 2,
    daily_cap: 2,
    credits_remaining: 1,
    eligible: false,
    unlock: {
      remaining_today: 0,
      daily_cap: 1,
      eligible: false,
      active: [{ template_id: PRO_LOOK, expires_at: EXPIRES }],
    },
  };
  const { deps, calls } = stub({ ad_reward_overview: { data: overview, error: null } });
  const { status, body } = await send(deps, appRequest("GET"));
  assert.equal(status, 200);
  assert.deepEqual(body, overview);
  assert.deepEqual(calls[0], { fn: "ad_reward_overview", args: { p_user: USER, p_is_pro: false, ...INSTALL } });
});

// MARK: - Release

Deno.test("release: a try's token gives its place back among the tries", async () => {
  const { deps, calls } = stub({
    release_ad_reward_token: { data: [{ released: true, remaining_today: 1, reward_kind: "unlock" }], error: null },
  });
  const { status, body } = await send(deps, appRequest("DELETE", `?token=${TOKEN}`));
  assert.equal(status, 200);
  assert.deepEqual(body, { released: true, kind: "unlock", remaining_today: 1, daily_cap: 1 });
  assert.deepEqual(calls[0], { fn: "release_ad_reward_token", args: { p_user: USER, p_token: TOKEN } });

  const credit = stub({ release_ad_reward_token: { data: [{ released: false, remaining_today: 0 }], error: null } });
  assert.deepEqual((await send(credit.deps, appRequest("DELETE", `?token=${TOKEN}`))).body, {
    released: false,
    kind: "credit",
    remaining_today: 0,
    daily_cap: 2,
  });
});
