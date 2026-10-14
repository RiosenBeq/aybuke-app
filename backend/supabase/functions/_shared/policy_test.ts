// deno test _shared/
import assert from "node:assert/strict";
import catalog from "./catalog.json" with { type: "json" };
import vectors from "./policy-vectors.json" with { type: "json" };
import { EDIT_GUARD, evaluatePrompt, forms, invalidTerms, words } from "./policy.ts";

type Vector = { lang: string; text: string; operation?: string; expected: string | null };

Deno.test("shared vectors match the app", () => {
  for (const vector of vectors.vectors as Vector[]) {
    const operation = vector.operation ?? "magic_edit";
    const verdict = evaluatePrompt(vector.text, operation);
    assert.equal(verdict.allowed ? null : verdict.category, vector.expected, `[${vector.lang}] ${vector.text}`);
    if (vector.expected === null && operation === "magic_edit") {
      const guarded = vector.text + EDIT_GUARD;
      assert.ok(evaluatePrompt(guarded, operation).allowed, guarded);
    }
  }
});

Deno.test("every term compiles", () => {
  assert.deepEqual(invalidTerms(), []);
});

Deno.test("template recipes and the guard pass", () => {
  assert.ok(evaluatePrompt(EDIT_GUARD, "magic_edit").allowed);
  for (const template of catalog.templates) {
    assert.ok(evaluatePrompt(template.prompt, "restyle").allowed, template.id);
  }
});

Deno.test("blocked requests carry the app's messages", () => {
  const verdict = evaluatePrompt("sexy teen", "text_to_image");
  assert.ok(!verdict.allowed && verdict.category === "sexualMinor" && verdict.reason.includes("violates"));
  assert.ok(evaluatePrompt("make me skinnier", "text_to_image").allowed);
});

Deno.test("normalisation matches ContentPolicy.words(in:)", () => {
  assert.deepEqual(words("BENİ ZAYIFLAT"), ["beni", "zayiflat"]);
  assert.deepEqual(words("Ｂｉｋｉｎｉ"), ["bikini"]);
  assert.deepEqual(words("b i k i n i at 5pm"), ["bikini", "at", "5pm"]);
  assert.deepEqual(words("s3xy 1990s 3d"), ["sexy", "1990s", "3d"]);
  assert.deepEqual(words("Crème brûlée"), ["creme", "brulee"]);
  assert.deepEqual(words("чёрный йогурт"), ["черный", "йогурт"]);
  assert.deepEqual(words("がんばって"), ["がんばって"]);
  assert.deepEqual(forms("skinnnnier"), ["skinnnnier", "skinnier", "skinier"]);
});
