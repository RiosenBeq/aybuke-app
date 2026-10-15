// Accounts (App Store Review Guideline 5.1.1(v) and Sign in with Apple).
//   POST   /account/link { "anonymous_token"?: JWT, "authorization_code"?: string }
//          Called right after Sign in with Apple, with the new session (and again until it
//          succeeds). Keeps Apple's refresh token so it can be revoked (exchanged first: the
//          code lasts five minutes), then moves the previous anonymous user's paid credits,
//          subscription, jobs and reports into the account and deletes that anonymous user.
//          → 200 { "linked": true, "merged": boolean, "token_stored": boolean }
//          → 500 merge_failed: nothing moved yet; the app retries with the same body.
//   DELETE /account { "anonymous_token"?: JWT, "authorization_code"?: string,
//          "skip_apple_revoke"?: true } → queues the RevenueCat customers (this user and
//          every anonymous user merged into it) for deletion, revokes the Sign in with Apple
//          token (the stored one, or one from a fresh `authorization_code`) and deletes the
//          user; wallets, ledger, jobs, entitlements and reports cascade. `anonymous_token`
//          is an anonymous user whose merge never finished; it is deleted too.
//          → 200 { "deleted": true, "apple_token_revoked": boolean }
//          → 409 apple_reauth_required: an Apple account with no stored token and no code;
//            nothing was deleted. The app runs Sign in with Apple again and sends its code
//            (or `skip_apple_revoke` when Apple can't give one).
//   POST   /account/revenuecat-deletions (service role only, scheduled with pg_cron) →
//          works through the RevenueCat deletions still waiting → { deleted, failed, waiting }
// Apple subscriptions are billed by Apple and must be cancelled by the user there.
import { requireServiceRole, requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import { databaseQueue, processRevenueCatDeletions } from "../_shared/revenuecat.ts";
import { accountDeps, type DeleteRequest, link, type LinkRequest, remove } from "./handler.ts";

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
      return await link(accountDeps(db), user, body);
    }
    if (req.method === "DELETE") {
      const user = await requireUser(db, req);
      const body = await req.json().catch(() => ({})) as DeleteRequest;
      return await remove(accountDeps(db), user, body);
    }
    throw new HttpError(405, "method_not_allowed", "Method not allowed.");
  } catch (error) {
    return errorResponse(error);
  }
});
