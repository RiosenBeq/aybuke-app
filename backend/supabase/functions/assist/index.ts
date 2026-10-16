// Writing help from Claude (Anthropic), shown in the app as Aybik; text only: never a photo.
//
//   POST /assist { "task": "inspire" | "magic" | "captions" | "makeup"
//                          | "looks" | "poll_questions" | "card_text" | "help",
//                  "text"?: string,      her words, at most 400 characters (optional for inspire,
//                                        poll_questions and card_text only)
//                  "locale": string,     the app's language: en, tr, es, pt-BR, fr, de, it, ru, ja, ko, zh-Hans, id
//                  "context"?: { "style"?, "format"?, "look"?, "a"?, "b"?: string }   each at most 100 characters
//                  "kinds"?: ["look" | "style" | "effect" | "enhance" | "glow"]       looks only (default: all)
//                  "slots": ["storyLine" | "coverMasthead" | "coverHeadline" | "stripCaption"] }  card_text only
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
//   looks    → 200 { "picks": [{ "kind", "id", "reason" }] }  1–3 items from catalog.json's "finder" for the
//              vibe she describes, best first, of the kinds she can use; `reason` ≤ 100 characters about the vibe
//   poll_questions → 200 { "suggestions": [string] }  up to 4 questions of ≤ 80 characters for her poll, about the
//              vibe, never looks; context.a / context.b say what pictures A and B are
//   card_text → 200 { "slots": { "<slot>": [string] } }  every slot asked for, up to 4 options each within its
//              length (storyLine 80, coverMasthead 10, coverHeadline 40, stripCaption 24); a slot can be []
//   help     → 200 { "answer": string, "support": boolean }  ≤ 600 characters of plain text from the server's
//              facts (help-facts.ts); `support` when it points her to the support page (or Feel good)
//
// Lines that go next to her photo (look reasons, poll questions, card text) pass the policy for a photo and
// may not talk about bodies, faces, skin or weight, rate looks, or hold links or @handles.
//
// Errors ({ "error": { "code", "message", … } }):
//   400 bad_request         a body that doesn't follow the contract
//   422 content_blocked     her words failed the prompt policy; `category` names it. No strike.
//   429 rate_limited        per user, per verified App Store install and per network address, each task's
//                           bucket an hour (assist_kind_policy(), 20261104000000: inspire, magic, captions
//                           and makeup 60/60/200, looks 30/30/120, poll_questions 20/20/100, card_text
//                           40/40/150, help 20/20/100); `retry_after` in seconds
//   503 assist_unavailable  no Anthropic key, AI paused, a result safety check failed in the last 5 minutes
//                           (Claude is left to the safety checks), a block or cool-down on her account or
//                           install, a ceiling reached (everyone: 20 a minute, 200 an hour, 1,000 a day;
//                           without a verified install: 30 an hour shared), Claude failed or took over 8 s,
//                           or nothing it wrote passed the checks. `retry_after` when the wait is known.
//                           The app falls back to its on-device writer and its own lists.
//
// Headers: Authorization (her session) and, optionally, X-App-Transaction
// (StoreKit's signed AppTransaction, verified as for ai-image: _shared/apple.ts).
// Without a verified install she shares the small unverified cap.
//
// Needs her session (verify_jwt, then requireUser); costs no credits. Every
// line Claude writes passes the prompt policy before it's returned. The logs
// carry counts and timings only, never her words or Claude's.
import { verifyInstall } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { askForJson, describeTextHelper, textHelperConfig } from "../_shared/claude-text.ts";
import { corsHeaders, errorResponse, HttpError } from "../_shared/http.ts";
import { clientIp } from "../_shared/input.ts";
import { type Admission, ASSIST_DEADLINE_MS, handleAssist, readJsonBody } from "./handler.ts";

console.info(`assist: ${describeTextHelper(textHelperConfig())}`);

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
      admit: async (kind) => {
        // Only once her words passed the policy: Apple's signature is checked as ai-image checks it.
        const install = await verifyInstall(req.headers.get("x-app-transaction"));
        const { data, error } = await db.rpc("admit_assist", {
          p_user: user.id,
          p_ip: ip ?? null,
          p_kind: kind,
          p_app_transaction_id: install.status === "verified" ? install.appTransactionId ?? null : null,
          p_install_status: install.status,
        });
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
