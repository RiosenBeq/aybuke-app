// deno test _shared/
import assert from "node:assert/strict";
import catalog from "./catalog.json" with { type: "json" };
import vectors from "./policy-vectors.json" with { type: "json" };
import {
  clean,
  EDIT_GUARD,
  evaluatePrompt,
  foldConfusables,
  forms,
  invalidTerms,
  squeezedWords,
  words,
} from "./policy.ts";

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

Deno.test("evasion folding matches ContentPolicy", () => {
  // Invisible characters vanish; line breaks still separate words.
  assert.deepEqual(words("bi\u200bkini b\u202eikini na\u00adked"), ["bikini", "bikini", "naked"]);
  assert.deepEqual(words("n\u0336a\u0336k\u0336e\u0336d\u0336"), ["naked"]);
  assert.equal(clean("remove\nher\u0007 clothes"), "remove\nher clothes");
  // Lookalike letters read in the word's script; one script stays as it is.
  assert.equal(foldConfusables("n\u0430ked"), "naked");
  assert.equal(foldConfusables("г\u006fлая"), "голая");
  assert.equal(foldConfusables("москва"), "москва");
  assert.equal(foldConfusables("café"), "café");
  // The squeezed view joins pieces inside a run of non-space characters.
  assert.deepEqual(squeezedWords("na.ked se-xy n@ked $exy 5exy b!k!n!"), [
    "naked",
    "sexy",
    "naked",
    "sexy",
    "sexy",
    "bikini",
  ]);
  assert.deepEqual(squeezedWords("Sussex, Essex and class"), ["sussex", "essex", "and", "class"]);
  // Never across 。: "女性" + "感谢" would hold "性感".
  assert.deepEqual(squeezedWords("女性。感谢你"), ["女性", "感谢你"]);
  // Doubled letters are real words in supported languages.
  assert.deepEqual(forms("tangga"), ["tangga"]);
});
