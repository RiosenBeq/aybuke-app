// Rewarded ads, for a credit or a one-time try of a Pro look or style: the
// routes and the contract are in handler.ts.
// Deploy with: supabase functions deploy ad-reward --no-verify-jwt
// (AdMob's callback carries no JWT: the handler checks Google's signature on
// it, and the user's session on the app's routes.)
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { VerifierKeys, verifyCallback } from "../_shared/admob.ts";
import { resolveEntitlement, verifyInstall } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { handleAdReward } from "./handler.ts";

const keys = new VerifierKeys();

Deno.serve((req) => {
  // Made on first use: a callback that fails Google's check never needs one.
  let client: SupabaseClient | undefined;
  const db = () => client ??= serviceClient();
  return handleAdReward(req, {
    rpc: (fn, args) => db().rpc(fn, args),
    requireUser: (request) => requireUser(db(), request),
    isPro: async (userId, jws) => (await resolveEntitlement(db(), userId, jws)).isPro,
    verifyInstall: (jws) => verifyInstall(jws),
    verifyCallback: (rawQuery) => verifyCallback(rawQuery, keys),
    env: Deno.env,
  });
});
