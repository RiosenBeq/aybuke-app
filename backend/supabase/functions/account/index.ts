// Accounts (App Store Review Guideline 5.1.1(v) and Sign in with Apple).
//   POST   /account/link { "anonymous_token"?: JWT, "authorization_code"?: string }
//          Called right after Sign in with Apple, with the new session. Moves the previous
//          anonymous user's paid credits, subscription, jobs and reports into the account,
//          deletes that anonymous user, and keeps Apple's refresh token so it can be revoked.
//          → 200 { "linked": true, "merged": boolean }
//   DELETE /account → revokes the Sign in with Apple token (if any) and deletes the user;
//          wallets, ledger, jobs, entitlements and reports cascade.
// Apple subscriptions are billed by Apple and must be cancelled by the user there.
import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2.117.3";
import { exchangeAuthorizationCode, revokeRefreshToken } from "../_shared/apple-signin.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";

interface LinkRequest {
  anonymous_token?: string;
  authorization_code?: string;
}

function isAppleAccount(user: User): boolean {
  return !user.is_anonymous && (user.identities ?? []).some((identity) => identity.provider === "apple");
}

async function link(db: SupabaseClient, user: User, body: LinkRequest): Promise<Response> {
  if (!isAppleAccount(user)) throw new HttpError(403, "forbidden", "Sign in with Apple first.");

  let merged = false;
  if (typeof body.anonymous_token === "string" && body.anonymous_token) {
    // Holding the anonymous user's session proves the caller owns it.
    const { data } = await db.auth.getUser(body.anonymous_token);
    const previous = data.user;
    if (previous?.is_anonymous && previous.id !== user.id) {
      const { error } = await db.rpc("merge_accounts", { p_from: previous.id, p_to: user.id });
      if (error) throw new HttpError(500, "internal", "Couldn't move your credits. Please try again.");
      const { error: deleteError } = await db.auth.admin.deleteUser(previous.id);
      if (deleteError) console.warn("couldn't delete merged anonymous user", previous.id);
      merged = true;
    }
  }

  if (typeof body.authorization_code === "string" && body.authorization_code) {
    const refreshToken = await exchangeAuthorizationCode(body.authorization_code);
    if (refreshToken) {
      await db.from("apple_accounts").upsert({
        user_id: user.id,
        refresh_token: refreshToken,
        updated_at: new Date().toISOString(),
      });
    }
  }
  return json({ linked: true, merged });
}

async function remove(db: SupabaseClient, user: User): Promise<Response> {
  const { data: apple } = await db.from("apple_accounts").select("refresh_token").eq("user_id", user.id).maybeSingle();
  if (apple?.refresh_token) {
    await revokeRefreshToken(apple.refresh_token).catch(() => false);
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
    if (req.method === "POST" && route === "link") {
      const user = await requireUser(db, req);
      const body = await req.json().catch(() => ({})) as LinkRequest;
      return await link(db, user, body);
    }
    if (req.method === "DELETE") {
      return await remove(db, await requireUser(db, req));
    }
    throw new HttpError(405, "method_not_allowed", "Method not allowed.");
  } catch (error) {
    return errorResponse(error);
  }
});
