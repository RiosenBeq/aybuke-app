// Rewarded ads: a short ad a free member chooses to watch, for one of two
// rewards. Never trusts the app to grant anything: only AdMob's signed
// callback does. Like the free credits, rewards belong to the verified App
// Store install (the app sends X-App-Transaction, see _shared/apple.ts and the
// 20261023 migration). The numbers are in ad_reward_policy().
//
//   * A credit ("credit"): when she's out of credits, at most 2 a day (UTC)
//     per user and per install.
//   * A Pro try ("unlock", migration 20261101000000): one Pro look (a restyle
//     template) or Pro Create style, for one job started within 30 minutes of
//     the reward; the job still costs a credit, so she needs one, and a
//     refunded job gives the try back for the rest of its time. At most 1 a
//     day per user and per install, counted apart from the credits.
//
//   POST   /ad-reward             → 201 { token, kind, expires_at, remaining_today, daily_cap,
//                                         template_id | style_id (a try) }
//          No body, {} or { "kind": "credit" }: a credit. { "kind": "unlock",
//          "template_id": "<Pro look>" } or { "kind": "unlock", "style_id":
//          "<Pro style>" }: a try of exactly that one. A single-use token for
//          the next ad, valid for 30 minutes: the app hands AdMob only this
//          token, as the server-side verification custom data.
//   GET    /ad-reward             → { remaining_today, daily_cap, credits_remaining, eligible,
//                                     unlock: { remaining_today, daily_cap, eligible,
//                                               active: [{ template_id | style_id, expires_at }] } }
//   GET    /ad-reward?token=ID    → { token, kind, status, remaining_today, daily_cap, credits_remaining,
//                                     template_id | style_id and, once granted, expires_at (a try) }
//          status: "pending" until AdMob calls back, then "granted", "capped"
//          or "expired"; "unknown" for a token that isn't hers. A granted
//          try's expires_at is when it can no longer start a job.
//   DELETE /ad-reward?token=ID    → { released, kind, remaining_today, daily_cap }
//          The ad closed before its reward, so the token's place comes back.
//   GET    /ad-reward?ad_network=…&…&signature=…&key_id=…
//          AdMob's server-side verification callback (no JWT: verify_jwt =
//          false in config.toml). Authenticated by Google's ECDSA signature,
//          the ad unit allow-list (ADMOB_REWARDED_AD_UNIT) and a live,
//          unredeemed token, whose kind decides what is paid. Fail-closed:
//          anything else grants nothing.
//
// remaining_today and daily_cap count the kind of reward in question. A
// daily_cap is null when the policy can't be read right now; the app keeps its
// copy. The other routes check the user's session themselves (requireUser),
// since the gateway doesn't. Contract: backend/README.md, "Rewarded ads", and
// ios/Packages/AppCore/Sources/AppCore/Ads.swift.
import { adUnitAllowed, isRewardToken, type RewardCallback, VerificationError } from "../_shared/admob.ts";
import { ADMISSION_MESSAGES } from "../_shared/admission.ts";
import type { InstallProof } from "../_shared/apple.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import { itemField, type ProItem, unlockRequest, type UnlockType } from "../_shared/unlocks.ts";
import { type AdCaps, readCaps } from "./cap.ts";

export interface RpcResult {
  data: unknown;
  error: { message: string } | null;
}

export interface AdRewardDeps {
  /** A database function, called with the service role (supabase-js `rpc`). */
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<RpcResult>;
  /** The user behind the request's session; throws a 401 HttpError without one. */
  requireUser(req: Request): Promise<{ id: string }>;
  /** Pro for this request (resolveEntitlement in _shared/apple.ts). */
  isPro(userId: string, entitlementJWS: string | null): Promise<boolean>;
  verifyInstall(appTransactionJWS: string | null): Promise<InstallProof>;
  /** Google's signature on the callback (verifyCallback in _shared/admob.ts). */
  verifyCallback(rawQuery: string): Promise<RewardCallback>;
  env: { get(name: string): string | undefined };
}

/** What POST /ad-reward asks for. */
export type RewardRequest = { kind: "credit" } | { kind: "unlock"; item: ProItem };

type Kind = RewardRequest["kind"];

/** The body is a few fields; anything bigger didn't come from the app. */
const MAX_BODY_BYTES = 4 * 1024;

export async function handleAdReward(req: Request, deps: AdRewardDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.has("signature")) {
    return await adMobCallback(req, deps);
  }
  try {
    const user = await deps.requireUser(req);
    const token = url.searchParams.get("token");
    switch (req.method) {
      case "POST": {
        const reward = await readRewardRequest(req);
        const isPro = await deps.isPro(user.id, req.headers.get("x-entitlement-jws"));
        const install = await deps.verifyInstall(req.headers.get("x-app-transaction"));
        return reward.kind === "unlock"
          ? await issueUnlockToken(deps, user.id, isPro, install, reward.item)
          : await issueToken(deps, user.id, isPro, install);
      }
      case "GET": {
        const isPro = await deps.isPro(user.id, req.headers.get("x-entitlement-jws"));
        if (token) return await tokenStatus(deps, user.id, token);
        return json(
          await loadOverview(deps, user.id, isPro, await deps.verifyInstall(req.headers.get("x-app-transaction"))),
        );
      }
      case "DELETE":
        if (!token || !isRewardToken(token)) throw new HttpError(400, "bad_request", "Missing token.");
        return await releaseToken(deps, user.id, token);
      default:
        throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    }
  } catch (error) {
    return errorResponse(error);
  }
}

// MARK: - The request

/**
 * A credit unless the body asks for a try: the app's ad for a credit sends no
 * body. A try names one Pro look or style (_shared/unlocks.ts).
 */
export async function readRewardRequest(req: Request): Promise<RewardRequest> {
  const text = await readSmallBody(req);
  if (!text.trim()) return { kind: "credit" };
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new HttpError(400, "bad_request", "Invalid JSON body.");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new HttpError(400, "bad_request", "Invalid JSON body.");
  }
  const fields = body as Record<string, unknown>;
  const kind = fields.kind ?? "credit";
  if (kind === "credit") return { kind: "credit" };
  if (kind !== "unlock") throw new HttpError(400, "bad_request", "Unknown reward.");
  return { kind: "unlock", item: unlockRequest(fields.template_id, fields.style_id) };
}

async function readSmallBody(req: Request): Promise<string> {
  const tooLarge = () => new HttpError(400, "bad_request", "Invalid JSON body.");
  if (Number(req.headers.get("content-length") ?? "0") > MAX_BODY_BYTES) throw tooLarge();
  const reader = req.body?.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (reader) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      throw tooLarge();
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

// MARK: - AdMob's callback

async function adMobCallback(req: Request, deps: AdRewardDeps): Promise<Response> {
  // The signed content is the query string exactly as sent: never re-encode it.
  const question = req.url.indexOf("?");
  const rawQuery = question >= 0 ? req.url.slice(question + 1) : "";
  let callback: RewardCallback;
  try {
    callback = await deps.verifyCallback(rawQuery);
  } catch (error) {
    if (error instanceof VerificationError) {
      console.warn("admob callback rejected", error.message);
      return json({ error: { code: "invalid_signature", message: "Verification failed." } }, 403);
    }
    // Google's keys couldn't be fetched: AdMob retries a few times.
    console.error("admob keys unavailable", error);
    return json({ error: { code: "unavailable", message: "Try again." } }, 503);
  }

  const allowList = deps.env.get("ADMOB_REWARDED_AD_UNIT");
  if (!allowList) {
    console.error("ADMOB_REWARDED_AD_UNIT is not set; refusing every reward");
    return json({ error: { code: "misconfigured", message: "Rewards are off." } }, 503);
  }
  if (!adUnitAllowed(callback.adUnit, allowList)) {
    // Genuinely Google's, but not one of our rewarded units (a replayed
    // callback from another app, say): nothing is granted, and no retries.
    console.warn("admob callback for another ad unit", callback.adUnit);
    return json({ ok: true, outcome: "unknown_ad_unit" });
  }
  if (!isRewardToken(callback.customData)) {
    // A verified callback without our token (the AdMob console's test callback,
    // say): acknowledged so AdMob stops retrying, and nothing is granted.
    console.warn("admob callback without a reward token", callback.transactionId);
    return json({ ok: true, outcome: "unknown" });
  }

  // The token says what the ad pays: a credit or a Pro try (redeem_ad_reward).
  let reply: RpcResult;
  try {
    reply = await deps.rpc("redeem_ad_reward", {
      p_transaction_id: callback.transactionId,
      p_token: callback.customData,
      p_ad_unit: callback.adUnit,
      p_reward_amount: Math.trunc(callback.rewardAmount),
      p_reward_item: callback.rewardItem.slice(0, 64),
    });
  } catch (error) {
    reply = { data: null, error: { message: error instanceof Error ? error.message : String(error) } };
  }
  if (reply.error) {
    console.error("redeem_ad_reward failed", reply.error.message);
    return json({ error: { code: "internal", message: "Try again." } }, 500);
  }
  const outcome = (reply.data as { outcome: string }[] | null)?.[0]?.outcome ?? "unknown";
  if (outcome !== "granted" && outcome !== "duplicate") {
    console.warn("admob reward not granted", outcome, callback.transactionId);
  }
  // 200 for every verified callback, so AdMob doesn't retry what can't change.
  return json({ ok: true, outcome });
}

// MARK: - The app's routes

function installParams(install: InstallProof): Record<string, string | null> {
  return {
    p_app_transaction_id: install.status === "verified" ? install.appTransactionId ?? null : null,
    p_install_status: install.status,
    p_install_environment: install.status === "verified" ? install.environment : null,
  };
}

/** The first row of a set-returning function. */
function firstRow<T>(data: unknown): T | undefined {
  return (Array.isArray(data) ? data[0] : undefined) as T | undefined;
}

/** A try's look or style as the app names it: { template_id } or { style_id }. */
function itemFields(type: unknown, id: unknown): Record<string, string> {
  if ((type !== "template" && type !== "style") || typeof id !== "string") return {};
  return { [itemField(type as UnlockType)]: id };
}

interface Overview {
  remaining_today: number;
  daily_cap: number;
  credits_remaining: number;
  eligible: boolean;
  unlock?: {
    remaining_today: number;
    daily_cap: number;
    eligible: boolean;
    active: Record<string, string>[];
  };
}

async function loadOverview(
  deps: AdRewardDeps,
  userId: string,
  isPro: boolean,
  install: InstallProof,
): Promise<Overview> {
  const { data, error } = await deps.rpc("ad_reward_overview", {
    p_user: userId,
    p_is_pro: isPro,
    ...installParams(install),
  });
  if (error || !data) throw new HttpError(500, "internal", "Couldn't check today's ads.");
  return data as Overview;
}

async function caps(deps: AdRewardDeps): Promise<AdCaps> {
  return await readCaps(() => deps.rpc("ad_reward_policy"));
}

async function issueToken(
  deps: AdRewardDeps,
  userId: string,
  isPro: boolean,
  install: InstallProof,
): Promise<Response> {
  const { data, error } = await deps.rpc("issue_ad_reward_token", {
    p_user: userId,
    p_is_pro: isPro,
    ...installParams(install),
  });
  if (error) {
    if (error.message.includes("AD_NOT_ELIGIBLE")) {
      throw new HttpError(403, "not_eligible", "Pro has no ads: your credits come every month.");
    }
    if (error.message.includes("AD_NO_INSTALL")) {
      // Nothing to count the daily cap on for this Apple Account: no ad.
      throw new HttpError(
        403,
        "not_eligible",
        "We couldn't confirm your download with the App Store, so ads can't add credits right now.",
      );
    }
    if (error.message.includes("AD_HAS_CREDITS")) {
      const { credits_remaining } = await loadOverview(deps, userId, isPro, install);
      throw new HttpError(409, "has_credits", "You still have credits to use.", credits_remaining);
    }
    if (error.message.includes("AD_DAILY_CAP")) {
      const cap = (await caps(deps)).credit;
      throw new HttpError(
        409,
        "daily_cap",
        cap === null
          ? "That's all your ad credits for today. More tomorrow."
          : `That's all ${cap} ad credits for today. More tomorrow.`,
      );
    }
    throw new HttpError(500, "internal", "Couldn't start the ad. Please try again.");
  }
  const row = firstRow<{ reward_token: string; valid_until: string; remaining_today: number }>(data);
  if (!row) throw new HttpError(500, "internal", "Couldn't start the ad. Please try again.");
  return json({
    token: row.reward_token,
    kind: "credit",
    expires_at: row.valid_until,
    remaining_today: row.remaining_today,
    daily_cap: (await caps(deps)).credit,
  }, 201);
}

async function issueUnlockToken(
  deps: AdRewardDeps,
  userId: string,
  isPro: boolean,
  install: InstallProof,
  item: ProItem,
): Promise<Response> {
  const { data, error } = await deps.rpc("issue_ad_unlock_token", {
    p_user: userId,
    p_is_pro: isPro,
    p_unlock_type: item.type,
    p_unlock_id: item.id,
    ...installParams(install),
  });
  if (error) {
    if (error.message.includes("AD_NOT_ELIGIBLE")) {
      throw new HttpError(
        403,
        "not_eligible",
        isPro
          ? "Pro already includes every look and style."
          : "Trying a Pro look with an ad isn't available right now.",
      );
    }
    if (error.message.includes("AD_NO_INSTALL")) {
      throw new HttpError(
        403,
        "not_eligible",
        "We couldn't confirm your download with the App Store, so ads can't unlock a look right now.",
      );
    }
    if (error.message.includes("AD_AI_PAUSED")) {
      throw new HttpError(503, "ai_paused", ADMISSION_MESSAGES.ai_paused);
    }
    if (error.message.includes("AD_NO_CREDITS")) {
      throw new HttpError(409, "no_credits", "Trying a Pro look uses 1 credit, and you're out of credits.", 0);
    }
    if (error.message.includes("AD_DAILY_CAP")) {
      const cap = (await caps(deps)).unlock;
      throw new HttpError(
        409,
        "daily_cap",
        cap === null || cap === 1
          ? "You've had today's Pro try. There's another one tomorrow."
          : `You've had all ${cap} Pro tries for today. More tomorrow.`,
      );
    }
    if (error.message.includes("AD_BAD_UNLOCK")) {
      throw new HttpError(400, "not_unlockable", "Only Pro looks and styles can be tried with an ad.");
    }
    throw new HttpError(500, "internal", "Couldn't start the ad. Please try again.");
  }
  const row = firstRow<{ reward_token: string; valid_until: string; remaining_today: number }>(data);
  if (!row) throw new HttpError(500, "internal", "Couldn't start the ad. Please try again.");
  return json({
    token: row.reward_token,
    kind: "unlock",
    ...itemFields(item.type, item.id),
    expires_at: row.valid_until,
    remaining_today: row.remaining_today,
    daily_cap: (await caps(deps)).unlock,
  }, 201);
}

interface StatusRow {
  outcome: string;
  remaining_today: number;
  credits_remaining: number;
  /** Since 20261101000000: the token's kind, and a try's look or style and end. */
  reward_kind?: string | null;
  unlock_type?: string | null;
  unlock_id?: string | null;
  unlock_expires_at?: string | null;
}

async function tokenStatus(deps: AdRewardDeps, userId: string, token: string): Promise<Response> {
  const daily = await caps(deps);
  if (!isRewardToken(token)) {
    return json({ token, status: "unknown", remaining_today: 0, daily_cap: daily.credit });
  }
  const { data, error } = await deps.rpc("ad_reward_status", { p_user: userId, p_token: token });
  const row = firstRow<StatusRow>(data);
  if (error || !row) throw new HttpError(500, "internal", "Couldn't check the ad. Please try again.");
  const kind: Kind = row.reward_kind === "unlock" ? "unlock" : "credit";
  const body: Record<string, unknown> = {
    token,
    kind,
    status: row.outcome,
    remaining_today: row.remaining_today,
    daily_cap: daily[kind],
    credits_remaining: row.credits_remaining,
  };
  if (kind === "unlock") {
    Object.assign(body, itemFields(row.unlock_type, row.unlock_id));
    if (row.outcome === "granted" && row.unlock_expires_at) body.expires_at = row.unlock_expires_at;
  }
  return json(body);
}

async function releaseToken(deps: AdRewardDeps, userId: string, token: string): Promise<Response> {
  const { data, error } = await deps.rpc("release_ad_reward_token", { p_user: userId, p_token: token });
  if (error) throw new HttpError(500, "internal", "Couldn't release the ad.");
  const row = firstRow<{ released: boolean; remaining_today: number; reward_kind?: string | null }>(data);
  const kind: Kind = row?.reward_kind === "unlock" ? "unlock" : "credit";
  return json({
    released: Boolean(row?.released),
    kind,
    remaining_today: row?.remaining_today ?? 0,
    daily_cap: (await caps(deps))[kind],
  });
}
