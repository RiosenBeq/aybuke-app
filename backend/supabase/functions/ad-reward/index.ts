// Rewarded ads: one credit for a watched ad, at most 2 a day (UTC) per user
// and per App Store install, for free members who are out of credits. Never
// trusts the app to grant anything: only AdMob's signed callback does. Like
// the free credits, ad credits belong to the verified install (the app sends
// X-App-Transaction, see _shared/apple.ts and the 20261023 migration).
//
//   POST   /ad-reward             → 201 { token, expires_at, remaining_today, daily_cap }
//          A single-use token for the next ad. The app hands AdMob only this
//          token, as the server-side verification custom data.
//   GET    /ad-reward             → { remaining_today, daily_cap, credits_remaining, eligible }
//   GET    /ad-reward?token=ID    → { token, status, remaining_today, daily_cap, credits_remaining }
//          status: "pending" until AdMob calls back, then "granted", "capped"
//          or "expired"; "unknown" for a token that isn't hers.
//   DELETE /ad-reward?token=ID    → { released, remaining_today, daily_cap }
//          The ad closed before its reward, so the token's place comes back.
//   GET    /ad-reward?ad_network=…&…&signature=…&key_id=…
//          AdMob's server-side verification callback (no JWT: verify_jwt =
//          false in config.toml). Authenticated by Google's ECDSA signature,
//          the ad unit allow-list (ADMOB_REWARDED_AD_UNIT) and a live,
//          unredeemed token. Fail-closed: anything else grants nothing.
//
// daily_cap is null when the policy can't be read right now; the app keeps its copy.
//
// The other routes check the user's session themselves (requireUser), since
// the gateway doesn't. Contract: ios/Packages/AppCore/Sources/AppCore/Ads.swift
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import {
  adUnitAllowed,
  isRewardToken,
  type RewardCallback,
  VerificationError,
  VerifierKeys,
  verifyCallback,
} from "../_shared/admob.ts";
import { type InstallProof, resolveEntitlement, verifyInstall } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import { readDailyCap } from "./cap.ts";

const keys = new VerifierKeys();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const url = new URL(req.url);
  if (req.method === "GET" && url.searchParams.has("signature")) {
    return await adMobCallback(req);
  }
  try {
    const db = serviceClient();
    const user = await requireUser(db, req);
    const token = url.searchParams.get("token");
    switch (req.method) {
      case "POST": {
        const { isPro } = await resolveEntitlement(db, user.id, req.headers.get("x-entitlement-jws"));
        const install = await verifyInstall(req.headers.get("x-app-transaction"));
        return await issueToken(db, user.id, isPro, install);
      }
      case "GET": {
        const { isPro } = await resolveEntitlement(db, user.id, req.headers.get("x-entitlement-jws"));
        if (token) return await tokenStatus(db, user.id, token);
        return await overview(db, user.id, isPro, await verifyInstall(req.headers.get("x-app-transaction")));
      }
      case "DELETE":
        if (!token || !isRewardToken(token)) throw new HttpError(400, "bad_request", "Missing token.");
        return await releaseToken(db, user.id, token);
      default:
        throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    }
  } catch (error) {
    return errorResponse(error);
  }
});

// MARK: - AdMob's callback

async function adMobCallback(req: Request): Promise<Response> {
  // The signed content is the query string exactly as sent: never re-encode it.
  const question = req.url.indexOf("?");
  const rawQuery = question >= 0 ? req.url.slice(question + 1) : "";
  let callback: RewardCallback;
  try {
    callback = await verifyCallback(rawQuery, keys);
  } catch (error) {
    if (error instanceof VerificationError) {
      console.warn("admob callback rejected", error.message);
      return json({ error: { code: "invalid_signature", message: "Verification failed." } }, 403);
    }
    // Google's keys couldn't be fetched: AdMob retries a few times.
    console.error("admob keys unavailable", error);
    return json({ error: { code: "unavailable", message: "Try again." } }, 503);
  }

  const allowList = Deno.env.get("ADMOB_REWARDED_AD_UNIT");
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

  const db = serviceClient();
  const { data, error } = await db.rpc("redeem_ad_reward", {
    p_transaction_id: callback.transactionId,
    p_token: callback.customData,
    p_ad_unit: callback.adUnit,
    p_reward_amount: Math.trunc(callback.rewardAmount),
    p_reward_item: callback.rewardItem.slice(0, 64),
  });
  if (error) {
    console.error("redeem_ad_reward failed", error.message);
    return json({ error: { code: "internal", message: "Try again." } }, 500);
  }
  const outcome = (data as { outcome: string }[] | null)?.[0]?.outcome ?? "unknown";
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

interface Overview {
  remaining_today: number;
  daily_cap: number;
  credits_remaining: number;
  eligible: boolean;
}

async function loadOverview(
  db: SupabaseClient,
  userId: string,
  isPro: boolean,
  install: InstallProof,
): Promise<Overview> {
  const { data, error } = await db.rpc("ad_reward_overview", {
    p_user: userId,
    p_is_pro: isPro,
    ...installParams(install),
  });
  if (error || !data) throw new HttpError(500, "internal", "Couldn't check today's ads.");
  return data as Overview;
}

async function issueToken(
  db: SupabaseClient,
  userId: string,
  isPro: boolean,
  install: InstallProof,
): Promise<Response> {
  const { data, error } = await db.rpc("issue_ad_reward_token", {
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
      const { credits_remaining } = await loadOverview(db, userId, isPro, install);
      throw new HttpError(409, "has_credits", "You still have credits to use.", credits_remaining);
    }
    if (error.message.includes("AD_DAILY_CAP")) {
      const cap = await dailyCap(db);
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
  const row = (data as { reward_token: string; valid_until: string; remaining_today: number }[])[0];
  return json({
    token: row.reward_token,
    expires_at: row.valid_until,
    remaining_today: row.remaining_today,
    daily_cap: await dailyCap(db),
  }, 201);
}

async function tokenStatus(db: SupabaseClient, userId: string, token: string): Promise<Response> {
  const cap = await dailyCap(db);
  if (!isRewardToken(token)) {
    return json({ token, status: "unknown", remaining_today: 0, daily_cap: cap });
  }
  const { data, error } = await db.rpc("ad_reward_status", { p_user: userId, p_token: token });
  if (error) throw new HttpError(500, "internal", "Couldn't check the ad. Please try again.");
  const row = (data as { outcome: string; remaining_today: number; credits_remaining: number }[])[0];
  return json({
    token,
    status: row.outcome,
    remaining_today: row.remaining_today,
    daily_cap: cap,
    credits_remaining: row.credits_remaining,
  });
}

async function overview(db: SupabaseClient, userId: string, isPro: boolean, install: InstallProof): Promise<Response> {
  return json(await loadOverview(db, userId, isPro, install));
}

async function releaseToken(db: SupabaseClient, userId: string, token: string): Promise<Response> {
  const { data, error } = await db.rpc("release_ad_reward_token", { p_user: userId, p_token: token });
  if (error) throw new HttpError(500, "internal", "Couldn't release the ad.");
  const row = (data as { released: boolean; remaining_today: number }[] | null)?.[0];
  return json({
    released: Boolean(row?.released),
    remaining_today: row?.remaining_today ?? 0,
    daily_cap: await dailyCap(db),
  });
}

// MARK: - Helpers

async function dailyCap(db: SupabaseClient): Promise<number | null> {
  return await readDailyCap(() => db.rpc("ad_reward_policy"));
}
