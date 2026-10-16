// The owner's admin API for the admin page on aybuke.org: see handler.ts and
// backend/README.md ("Admin API").
// Deploy with: supabase functions deploy admin   (JWT verification stays on:
// the page sends the public anon key; x-admin-token is the real check)
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { serviceClient } from "../_shared/auth.ts";
import { clientIp } from "../_shared/input.ts";
import { handleAdmin, parseDigest } from "./handler.ts";

if (!parseDigest(Deno.env.get("ADMIN_TOKEN_SHA256"))) {
  console.warn("admin: ADMIN_TOKEN_SHA256 isn't set to 64 hex characters, so every call gets a 503");
}

Deno.serve((req) => {
  let client: SupabaseClient | undefined;
  const db = () => client ??= serviceClient();
  return handleAdmin(req, {
    env: Deno.env,
    rpc: (fn, args) => db().rpc(fn, args).abortSignal(AbortSignal.timeout(15_000)),
    clientIp: (request) => clientIp(request.headers),
    now: () => new Date(),
    log: (entry) => console.info(JSON.stringify(entry)),
  });
});
