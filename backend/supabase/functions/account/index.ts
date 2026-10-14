// Accounts (App Store Review Guideline 5.1.1(v) and Sign in with Apple).
//   POST   /account/link { "anonymous_token"?: JWT, "authorization_code"?: string }
//          Called right after Sign in with Apple, with the new session. Moves the previous
//          anonymous user's paid credits, subscription, jobs and reports into the account,
//          deletes that anonymous user, and keeps Apple's refresh token so it can be revoked.
//          → 200 { "linked": true, "merged": boolean }
//   DELETE /account { "anonymous_token"?: JWT } → queues the RevenueCat customers (this
//          user and every anonymous user merged into it) for deletion, revokes the Sign in
//          with Apple token (if any) and deletes the user; wallets, ledger, jobs,
//          entitlements and reports cascade. `anonymous_token` is an anonymous user whose
//          merge never finished; it is deleted too.
//   POST   /account/revenuecat-deletions (service role only, scheduled with pg_cron) →
//          works through the RevenueCat deletions still waiting → { deleted, failed, waiting }
// Apple subscriptions are billed by Apple and must be cancelled by the user there.
import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2.117.3";
import { appleSignInConfigured, exchangeAuthorizationCode, revokeRefreshToken } from "../_shared/apple-signin.ts";
import { requireServiceRole, requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import { databaseQueue, deleteRevenueCatCustomers, processRevenueCatDeletions } from "../_shared/revenuecat.ts";

interface LinkRequest {
  anonymous_token?: string;
  authorization_code?: string;
}

interface DeleteRequest {
  anonymous_token?: string;
}

function isAppleAccount(user: User): boolean {
  return !user.is_anonymous && (user.identities ?? []).some((identity) => identity.provider === "apple");
}

// Holding an anonymous user's session proves the caller owns it.
async function ownedAnonymousUser(db: SupabaseClient, token: unknown, owner: User): Promise<User | null> {
  if (typeof token !== "string" || !token) return null;
  const { data } = await db.auth.getUser(token);
  const previous = data.user;
  return previous?.is_anonymous && previous.id !== owner.id ? previous : null;
}

async function link(db: SupabaseClient, user: User, body: LinkRequest): Promise<Response> {
  if (!isAppleAccount(user)) throw new HttpError(403, "forbidden", "Sign in with Apple first.");

  let merged = false;
  const previous = await ownedAnonymousUser(db, body.anonymous_token, user);
  if (previous) {
    // Recorded first: RevenueCat keeps purchases made while anonymous on that
    // customer, so deleting the account must find it.
    const { error: recordError } = await db.from("merged_users").upsert({
      account_id: user.id,
      anonymous_id: previous.id,
    });
    if (recordError) throw new HttpError(500, "internal", "Couldn't move your credits. Please try again.");
    const { error } = await db.rpc("merge_accounts", { p_from: previous.id, p_to: user.id });
    if (error) throw new HttpError(500, "internal", "Couldn't move your credits. Please try again.");
    const { error: deleteError } = await db.auth.admin.deleteUser(previous.id);
    if (deleteError) console.warn("couldn't delete merged anonymous user", previous.id);
    merged = true;
  }

  if (typeof body.authorization_code === "string" && body.authorization_code) {
    // The merge is done; a failed exchange only means the token can't be revoked later.
    const refreshToken = await exchangeAuthorizationCode(body.authorization_code).catch((error) => {
      console.error("apple code exchange failed", error instanceof Error ? error.message : error);
      return null;
    });
    if (refreshToken) {
      await db.from("apple_accounts").upsert({
        user_id: user.id,
        refresh_token: refreshToken,
        updated_at: new Date().toISOString(),
      });
    } else {
      console.warn("no Apple refresh token stored for", user.id, "so deleting this account can't revoke it");
    }
  }
  return json({ linked: true, merged });
}

async function remove(db: SupabaseClient, user: User, body: DeleteRequest): Promise<Response> {
  const unmerged = await ownedAnonymousUser(db, body.anonymous_token, user);
  const { data: mergedRows } = await db.from("merged_users").select("anonymous_id").eq("account_id", user.id);
  // Queued before the user is deleted, so a failed deletion can be retried and
  // still find the merged ids; without the key they wait in the queue. Never
  // fails the deletion.
  await deleteRevenueCatCustomers(databaseQueue(db), [
    user.id,
    ...(mergedRows ?? []).map((row) => String(row.anonymous_id)),
    ...(unmerged ? [unmerged.id] : []),
  ]);
  if (unmerged) {
    const { error } = await db.auth.admin.deleteUser(unmerged.id);
    if (error) throw new HttpError(500, "internal", "Couldn't delete your account. Please contact support.");
  }
  const { data: apple } = await db.from("apple_accounts").select("refresh_token").eq("user_id", user.id).maybeSingle();
  if (apple?.refresh_token) {
    const revoked = await revokeRefreshToken(apple.refresh_token).catch((error) => {
      console.error("apple token revocation failed", error instanceof Error ? error.message : error);
      return false;
    });
    if (!revoked) console.error("Sign in with Apple token NOT revoked for deleted account", user.id);
  } else if (isAppleAccount(user)) {
    console.error(
      "Sign in with Apple account deleted without a stored token to revoke",
      user.id,
      appleSignInConfigured() ? "" : "(APPLE_TEAM_ID / APPLE_SIGNIN_KEY_ID / APPLE_SIGNIN_PRIVATE_KEY not set)",
    );
  }
  const { error } = await db.auth.admin.deleteUser(user.id);
  if (error) throw new HttpError(500, "internal", "Couldn't delete your account. Please contact support.");
  return json({ deleted: true });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const db = serviceClient();
    const route = new URL(req.url).pathname.replace(/\/+$/, "").split("/").pop();
    if (req.method === "POST" && route === "revenuecat-deletions") {
      requireServiceRole(req);
      return json(await processRevenueCatDeletions(databaseQueue(db)));
    }
    if (req.method === "POST" && route === "link") {
      const user = await requireUser(db, req);
      const body = await req.json().catch(() => ({})) as LinkRequest;
      return await link(db, user, body);
    }
    if (req.method === "DELETE") {
      const user = await requireUser(db, req);
      const body = await req.json().catch(() => ({})) as DeleteRequest;
      return await remove(db, user, body);
    }
    throw new HttpError(405, "method_not_allowed", "Method not allowed.");
  } catch (error) {
    return errorResponse(error);
  }
});
