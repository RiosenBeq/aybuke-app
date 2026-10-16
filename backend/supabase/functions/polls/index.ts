// "Which vibe?" polls with friends: the routes and the contract are in
// handler.ts and backend/README.md ("Polls").
// Deploy with: supabase functions deploy polls   (JWT verification stays on:
// the app sends her session, the poll page on aybuke.org the public anon key)
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { verifyInstall } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { requireEnv } from "../_shared/http.ts";
import { clientIp } from "../_shared/input.ts";
import { classifyImages, safetyConfig } from "../_shared/safety.ts";
import { handlePolls } from "./handler.ts";

// Polls need Claude: the privacy policies name Anthropic as the check of poll
// pictures, so the xAI fallback of the other checks (XAI_SAFETY_MODEL) doesn't
// count here. Without ANTHROPIC_API_KEY no poll is made (503).
const safety = safetyConfig();
const claude = safety?.provider === "anthropic" ? safety : undefined;
console.info(`polls: picture check ${claude ? `anthropic:${claude.model}` : "off (no poll can be made)"}`);

/** The role in a JWT the gateway already verified: only to skip an Auth call for the anon key. */
function tokenRole(req: Request): string | undefined {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const payload = token.split(".")[1];
  if (!payload) return undefined;
  try {
    const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    return typeof claims?.role === "string" ? claims.role : undefined;
  } catch {
    return undefined;
  }
}

Deno.serve((req) => {
  let client: SupabaseClient | undefined;
  const db = () => client ??= serviceClient();
  return handlePolls(req, {
    rpc: (fn, args) => db().rpc(fn, args),
    requireUser: (request) => requireUser(db(), request),
    sessionUser: async (request) => {
      if (tokenRole(request) !== "authenticated") return null;
      try {
        return (await requireUser(db(), request)).id;
      } catch {
        return null;
      }
    },
    verifyInstall: (jws) => verifyInstall(jws),
    checkPicture: claude
      ? (picture) =>
        classifyImages([picture], "share", {
          provider: "anthropic",
          model: claude.model,
          apiKey: Deno.env.get("ANTHROPIC_API_KEY") ?? "",
        })
      : undefined,
    signingSecret: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    publicBase: `${requireEnv("SUPABASE_URL").replace(/\/+$/, "")}/functions/v1/polls`,
    clientIp: (request) => clientIp(request.headers),
    now: () => new Date(),
    log: (entry) => console.info(JSON.stringify(entry)),
  });
});
