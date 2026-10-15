// Writing help from Claude (Anthropic), text only: never a photo.
//
//   POST /assist { "task": "inspire" | "magic" | "captions" | "makeup",
//                  "text"?: string,      her words, at most 400 characters (needed by all but inspire)
//                  "locale": string,     the app's language: en, tr, es, pt-BR, fr, de, it, ru, ja, ko, zh-Hans, id
//                  "context"?: { "style"?: string, "format"?: string, "look"?: string } }
//   inspire  → 200 { "suggestions": [string] }  up to 4 ideas for a new picture, ≤ 120 characters each
//   magic    → 200 { "suggestions": [string] }  1–2 richer rewrites of her Create prompt, ≤ 300 characters each
//   captions → 200 { "suggestions": [string] }  up to 4 captions about the vibe, never her looks, ≤ 120
//              characters, 1–3 hashtags at most; context.format is the share design (story, cover, strip…)
//   makeup   → 200 { "makeup": { "look", "lips", "lipFinish", "eyes", "cheeks", "extras": [], "hair", "intensity" },
//                    "note": string }
//              Makeup Studio ids only (catalog.json's "makeup"; unknown ids are dropped). Every field is the
//              final pick: a look comes with its whole recipe, with any part Claude chose on top and extras
//              added to the look's (3 at most); a lip finish only with lips; null means as is. `note` is one
//              line in her language, or "" when it didn't pass the checks.
//
// Errors ({ "error": { "code", "message", … } }):
//   400 bad_request         a body that doesn't follow the contract
//   422 content_blocked     her words failed the prompt policy; `category` names it. No strike.
//   429 rate_limited        60 an hour per user, 200 an hour per network address (admit_assist(),
//                           20261031000000); `retry_after` in seconds
//   503 assist_unavailable  ANTHROPIC_API_KEY unset, AI paused by the owner, a block or cool-down on her
//                           account, Claude failed or took over 8 s, or nothing it wrote passed the checks.
//                           The app falls back to its on-device writer and its own lists.
//
// Needs her session (verify_jwt, then requireUser); costs no credits. Every
// line Claude writes passes the prompt policy before it's returned. The logs
// carry counts and timings only, never her words or Claude's.
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { askForJson, textHelperConfig } from "../_shared/claude-text.ts";
import { corsHeaders, errorResponse, HttpError } from "../_shared/http.ts";
import { clientIp } from "../_shared/input.ts";
import { type Admission, ASSIST_DEADLINE_MS, handleAssist, readJsonBody } from "./handler.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    const db = serviceClient();
    const user = await requireUser(db, req);
    const body = await readJsonBody(req);
    const ip = clientIp(req.headers);
    const config = textHelperConfig();
    return await handleAssist({
      enabled: config !== undefined,
      admit: async () => {
        const { data, error } = await db.rpc("admit_assist", { p_user: user.id, p_ip: ip ?? null, p_kind: "assist" });
        if (error || !data) {
          console.error("admit_assist failed", error?.message);
          return null;
        }
        return data as Admission;
      },
      ask: (task) =>
        config
          ? askForJson(config, task, { deadlineMs: ASSIST_DEADLINE_MS })
          : Promise.resolve({ ok: false, detail: "off" }),
      now: () => new Date(),
      log: (entry) => console.info(JSON.stringify(entry)),
    }, body);
  } catch (error) {
    return errorResponse(error);
  }
});
