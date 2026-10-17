// The owner's admin API for the admin page on aybuke.org: see handler.ts and
// backend/README.md ("Admin API").
// Deploy with: supabase functions deploy admin   (JWT verification stays on:
// the page sends the owner's session, or the public anon key with
// x-admin-token; the function checks either one)
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { serviceClient } from "../_shared/auth.ts";
import { clientIp } from "../_shared/input.ts";
import { handleAdmin, parseAdminEmails, parseDigest, type SessionUser } from "./handler.ts";

if (!parseDigest(Deno.env.get("ADMIN_TOKEN_SHA256")) && parseAdminEmails(Deno.env.get("ADMIN_EMAILS")).size === 0) {
  console.warn(
    "admin: neither ADMIN_EMAILS nor ADMIN_TOKEN_SHA256 (64 hex characters) is set, so every call gets a 503",
  );
}

const AUTH_TIMEOUT_MS = 10_000;

Deno.serve((req) => {
  let client: SupabaseClient | undefined;
  const db = () => client ??= serviceClient();
  return handleAdmin(req, {
    env: Deno.env,
    rpc: (fn, args) => db().rpc(fn, args).abortSignal(AbortSignal.timeout(15_000)),
    getUser: async (jwt): Promise<SessionUser | null> => {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const timeout = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error("auth timed out")), AUTH_TIMEOUT_MS);
      });
      try {
        const { data, error } = await Promise.race([db().auth.getUser(jwt), timeout]);
        if (!error) return data.user ?? null;
        // A 4xx (bad, expired or signed-out session) is an answer; anything else means it can't be asked.
        const status = typeof error.status === "number" ? error.status : 0;
        if (status >= 400 && status < 500 && status !== 429) return null;
        throw new Error("auth unavailable");
      } finally {
        clearTimeout(timer);
      }
    },
    clientIp: (request) => clientIp(request.headers),
    now: () => new Date(),
    log: (entry) => console.info(JSON.stringify(entry)),
  });
});
