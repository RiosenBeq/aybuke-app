// The owner's daily digest mail: see handler.ts.
// Deploy with: supabase functions deploy owner-digest   (JWT verification stays on:
// the workflow sends the public anon key, and x-digest-secret is the real check)
import { serviceClient } from "../_shared/auth.ts";
import { sendOwnerMail } from "../_shared/owner-mail.ts";
import { databaseQueue, processRevenueCatDeletions, revenueCatKey } from "../_shared/revenuecat.ts";
import { handleDigest } from "./handler.ts";

async function rpc(name: string, args?: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await serviceClient().rpc(name, args).abortSignal(AbortSignal.timeout(15_000));
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

Deno.serve((req) =>
  handleDigest(req, {
    env: Deno.env,
    members: () => rpc("ops_members_summary"),
    daily: (day) => rpc("ops_daily_summary", { p_day: day }),
    budget: () => rpc("ops_provider_budget", { p_provider: "xai" }),
    revenueCat: () => rpc("ops_revenuecat_pending", { p_limit: 20 }),
    // The hourly retry needs pg_net, which is off: with the key set, the digest is the daily pass.
    deleteRevenueCat: revenueCatKey()
      ? () => processRevenueCatDeletions(databaseQueue(serviceClient()), { limit: 20 })
      : undefined,
    send: (mail) => sendOwnerMail(mail),
  })
);
