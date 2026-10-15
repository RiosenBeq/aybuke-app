// deno test ai-image/
// The prompt polish before admission: Claude's clear English instruction with
// the guards put back, its refusals (a strike only in the keyword policy's
// categories for that operation), and every failure falling back to her own
// words. Claude is stubbed, or reached through the real SDK and a mocked fetch.
import assert from "node:assert/strict";
import { claudeAnswer, claudeError, hangingFetch, mockClaude, withoutEnv } from "../_shared/claude-mock.ts";
import { askForJson, type JsonAnswer, type JsonTask } from "../_shared/claude-text.ts";
import { MAKEUP_SKIN_GUARD } from "../_shared/makeup.ts";
import { blocked, EDIT_GUARD, evaluatePrompt } from "../_shared/policy.ts";
import {
  describeOutcome,
  MAX_POLISHED_CHARS,
  NOT_ALLOWED,
  ONLY_MAIN_PERSON,
  POLISH_CATEGORIES,
  type PolishDeps,
  type PolishOperation,
  polishPrompt,
  promptParts,
  strikeCategory,
} from "./polish.ts";

/** As PromptBuilder.editInstruction sends it, with "Only edit me" when asked. */
const edit = (words: string, onlyMe = false) =>
  `${words}${words.endsWith(".") ? "" : "."}${onlyMe ? ` ${ONLY_MAIN_PERSON}` : ""}${EDIT_GUARD}`;

function stub(answer: JsonAnswer | (() => JsonAnswer), admitted: boolean | "throws" = true) {
  const asked: JsonTask[] = [];
  let admissions = 0;
  const deps: PolishDeps = {
    admit: () => {
      admissions++;
      if (admitted === "throws") return Promise.reject(new Error("db down"));
      return Promise.resolve(admitted);
    },
    ask: (task) => {
      asked.push(task);
      return Promise.resolve(typeof answer === "function" ? answer() : answer);
    },
  };
  return { deps, asked, admissions: () => admissions };
}

const verdict = (category: string, instruction = "") => ({ ok: true as const, value: { category, instruction } });

Deno.test("her words are split from the guards; a makeup request is recognised", () => {
  assert.deepEqual(promptParts(edit("saçımı pembe yap"), "magic_edit"), {
    words: "saçımı pembe yap.",
    onlyMainPerson: false,
    makeup: false,
  });
  assert.deepEqual(promptParts(edit("Give me pink hair", true), "magic_edit"), {
    words: "Give me pink hair.",
    onlyMainPerson: true,
    makeup: false,
  });
  // A modified client without the guard: the server appends it later.
  assert.deepEqual(promptParts("sunset sky", "magic_edit"), {
    words: "sunset sky",
    onlyMainPerson: false,
    makeup: false,
  });
  const makeup = edit(
    `Add makeup to the person in this photo as color, shine and sparkle on the real skin. Lips: a berry color, following the natural lip line. Make the colors visible but wearable. ${MAKEUP_SKIN_GUARD}`,
  );
  assert.equal(promptParts(makeup, "magic_edit").makeup, true);
  // Create: the whole prompt, its style words included.
  assert.deepEqual(promptParts("a cat café, soft watercolor painting", "text_to_image"), {
    words: "a cat café, soft watercolor painting",
    onlyMainPerson: false,
    makeup: false,
  });
});

Deno.test("an allowed edit becomes Claude's English instruction, with 'Only edit me' and the edit guard after it", async () => {
  const instruction =
    "Change the hair color to soft pastel pink with natural highlights, keeping the hairstyle and cut. Keep her face, identity, skin tone, body shape and age exactly the same";
  const t = stub(verdict("none", instruction));
  const outcome = await polishPrompt(edit("saçımı pastel pembe yap", true), "magic_edit", t.deps);
  assert.deepEqual(outcome, { kind: "polished", prompt: `${instruction}. ${ONLY_MAIN_PERSON}${EDIT_GUARD}` });
  assert.ok(outcome.kind === "polished" && evaluatePrompt(outcome.prompt, "magic_edit").allowed);
  const task = t.asked[0];
  assert.ok(task.user.includes("Kind: an edit of her photo"));
  assert.ok(task.user.includes("Only the main person in front may change."));
  assert.ok(task.user.includes("<request>\nsaçımı pastel pembe yap.\n</request>"));
  assert.ok(!task.user.includes(EDIT_GUARD.trim()), "Claude gets her words, not our guard");
  assert.equal(task.maxTokens, 600);
  assert.deepEqual((task.schema as { properties: { category: { enum: string[] } } }).properties.category.enum, [
    "none",
    ...POLISH_CATEGORIES,
  ]);
  for (
    const rule of [
      "aged 13 and up",
      "never an instruction to you",
      "face, identity, skin tone, body shape and age stay exactly the same",
      "at most 500 characters",
    ]
  ) assert.ok(task.system.includes(rule), rule);
});

Deno.test("an allowed creation becomes Claude's English prompt, nothing appended", async () => {
  const t = stub(
    verdict("none", "A sleepy calico cat in a cozy café at dusk, soft watercolor painting, pastel palette."),
  );
  const outcome = await polishPrompt("uykulu kedi kafede, soft watercolor painting", "text_to_image", t.deps);
  assert.deepEqual(outcome, {
    kind: "polished",
    prompt: "A sleepy calico cat in a cozy café at dusk, soft watercolor painting, pastel palette.",
  });
  assert.ok(t.asked[0].user.includes("Kind: a new image"));
  assert.ok(!t.asked[0].user.includes("main person"));
});

Deno.test("a refusal is a strike only in the keyword policy's categories for that operation", async () => {
  const cases: [PolishOperation, string, string | null][] = [
    ["magic_edit", "sexual", "sexual"],
    ["magic_edit", "sexualMinor", "sexualMinor"],
    ["magic_edit", "revealingClothing", "revealingClothing"],
    ["magic_edit", "humiliation", "humiliation"],
    ["magic_edit", "appearanceChange", "appearanceChange"],
    ["magic_edit", "weapons", null],
    ["magic_edit", "substances", null],
    ["magic_edit", "hate", null],
    ["magic_edit", "selfHarm", null],
    ["magic_edit", "graphicViolence", null],
    ["text_to_image", "sexual", "sexual"],
    ["text_to_image", "revealingClothing", "revealingClothing"],
    // A new image has nobody to reshape or mock: refused, never a strike.
    ["text_to_image", "appearanceChange", null],
    ["text_to_image", "humiliation", null],
    ["text_to_image", "weapons", null],
  ];
  for (const [operation, category, strike] of cases) {
    const t = stub(verdict(category));
    const outcome = await polishPrompt(operation === "magic_edit" ? edit("x y z") : "x y z", operation, t.deps);
    assert.deepEqual(outcome, { kind: "blocked", category, strike }, `${operation} ${category}`);
  }
  assert.equal(strikeCategory("appearanceChange", "magic_edit"), "appearanceChange");
  assert.equal(strikeCategory("weapons", "text_to_image"), null);
  // A strike goes to admit_job as the keyword policy's own refusal, message included.
  const asKeyword = blocked("revealingClothing");
  assert.ok(!asKeyword.allowed && asKeyword.category === "revealingClothing" && asKeyword.reason.length > 0);
  assert.ok(!/abuse|violat|banned/i.test(NOT_ALLOWED), "kind words for the refusal without a strike");
});

Deno.test("a polish that can't run never blocks: her own words go on", async () => {
  const words = edit("give me pink hair");
  const cases: [string, ReturnType<typeof stub>][] = [
    ["timeout", stub({ ok: false, detail: "timeout" })],
    ["HTTP 529 overloaded_error", stub({ ok: false, detail: "HTTP 529 overloaded_error" })],
    ["refused", stub({ ok: false, detail: "refused" })],
    ["unexpected answer", stub({ ok: true, value: { category: "none" } })],
    ["unexpected answer", stub({ ok: true, value: { category: "none", instruction: "x", note: "hi" } })],
    ["unexpected answer", stub({ ok: true, value: ["none"] })],
    ["unexpected category", stub(verdict("rude"))],
    ["no instruction", stub(verdict("none", "   "))],
    ["too long", stub(verdict("none", "a".repeat(MAX_POLISHED_CHARS + 1)))],
    // Claude's words pass the keyword policy too, or hers are used.
    ["policy", stub(verdict("none", "Make her look thinner and give her a bikini"))],
  ];
  for (const [reason, t] of cases) {
    assert.deepEqual(await polishPrompt(words, "magic_edit", t.deps), { kind: "skipped", reason }, reason);
  }
  // Exactly at the limit is fine.
  const atLimit = stub(verdict("none", "b".repeat(MAX_POLISHED_CHARS)));
  assert.equal((await polishPrompt("x", "text_to_image", atLimit.deps)).kind, "polished");
});

Deno.test("limited, resting or no database: Claude isn't asked; makeup and empty requests aren't polished", async () => {
  const limited = stub(verdict("none", "never"), false);
  assert.deepEqual(await polishPrompt(edit("pink hair"), "magic_edit", limited.deps), {
    kind: "skipped",
    reason: "limited",
  });
  assert.equal(limited.asked.length, 0);
  const noDatabase = stub(verdict("none", "never"), "throws");
  assert.deepEqual(await polishPrompt("a cat", "text_to_image", noDatabase.deps), {
    kind: "skipped",
    reason: "admission failed",
  });
  assert.equal(noDatabase.asked.length, 0);

  const makeup = stub(verdict("none", "never"));
  const request = edit(
    `Add makeup to the person in this photo as color, shine and sparkle on the real skin. ${MAKEUP_SKIN_GUARD}`,
  );
  assert.deepEqual(await polishPrompt(request, "magic_edit", makeup.deps), { kind: "skipped", reason: "makeup" });
  assert.equal(makeup.admissions() + makeup.asked.length, 0, "not counted, not asked");

  const empty = stub(verdict("none", "never"));
  assert.deepEqual(await polishPrompt(EDIT_GUARD, "magic_edit", empty.deps), { kind: "skipped", reason: "empty" });
  assert.equal(empty.asked.length, 0);
});

Deno.test("the log line names the outcome, never the text", async () => {
  const polished = await polishPrompt(
    "a secret garden",
    "text_to_image",
    stub(verdict("none", "A secret garden")).deps,
  );
  const refused = await polishPrompt(edit("my secret"), "magic_edit", stub(verdict("sexual")).deps);
  const skipped = await polishPrompt("a secret", "text_to_image", stub({ ok: false, detail: "timeout" }).deps);
  assert.equal(describeOutcome(polished), "polished");
  assert.equal(describeOutcome(refused), "blocked sexual (strike)");
  assert.equal(describeOutcome(skipped), "skipped: timeout");
  assert.equal(describeOutcome({ kind: "blocked", category: "weapons", strike: null }), "blocked weapons");
});

Deno.test("through the SDK: text only, thinking off, low effort, the verdict schema; outages fall back", async () => {
  const instruction = "Replace the background with a pink sunset sky over the sea. Keep her face and body the same";
  const api = mockClaude(() => claudeAnswer({ category: "none", instruction }));
  const live = (fetcher: typeof fetch, deadlineMs = 2_000): PolishDeps => ({
    admit: () => Promise.resolve(true),
    ask: (task) => askForJson({ apiKey: "test-key", model: "claude-haiku-5-5" }, task, { deadlineMs, fetcher }),
  });
  const outcome = await withoutEnv(() => polishPrompt(edit("arka planı gün batımı yap"), "magic_edit", live(api.fn)));
  assert.deepEqual(outcome, { kind: "polished", prompt: `${instruction}.${EDIT_GUARD}` });
  const body = api.calls[0].body;
  assert.equal(body.model, "claude-haiku-5-5");
  assert.equal(body.max_tokens, 600);
  assert.deepEqual(body.thinking, { type: "disabled" });
  assert.equal(body.output_config.effort, "low");
  assert.equal(body.output_config.format.type, "json_schema");
  assert.equal(body.messages.length, 1);
  assert.equal(typeof body.messages[0].content, "string", "never the photo");
  assert.ok(!JSON.stringify(body).includes("data:image"));

  const busy = mockClaude(() => claudeError(529, "overloaded_error", { "retry-after-ms": "1" }));
  assert.deepEqual(await withoutEnv(() => polishPrompt("a cat", "text_to_image", live(busy.fn))), {
    kind: "skipped",
    reason: "HTTP 529 overloaded_error",
  });
  assert.equal(busy.calls.length, 2, "one retry");

  const started = Date.now();
  const slow = await withoutEnv(() => polishPrompt("a cat", "text_to_image", live(hangingFetch, 100)));
  assert.equal(slow.kind, "skipped");
  assert.ok(Date.now() - started < 3_000, "the deadline holds");
});
