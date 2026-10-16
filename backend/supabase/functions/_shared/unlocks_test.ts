// deno test _shared/
// What a Pro try may be for (migration 20261101000000): one Pro look or Pro
// style from the catalog, named once. ai-image's side is in
// ai-image/pro_try_test.ts, the database's in
// backend/supabase/tests/rewarded_unlocks_test.sql.
import assert from "node:assert/strict";
import catalog from "./catalog.json" with { type: "json" };
import { HttpError } from "./http.ts";
import { PRO_STYLES, templateRecipe } from "./templates.ts";
import { isUnlockable, itemField, proItemsFor, unlockRequest } from "./unlocks.ts";

const PRO_LOOK = catalog.templates.find((template) => template.isPro)!.id;
const FREE_LOOK = catalog.templates.find((template) => !template.isPro)!.id;
const PRO_STYLE = catalog.proStyles[0];

function refused(run: () => unknown, status: number, code: string) {
  assert.throws(run, (error: unknown) => {
    assert.ok(error instanceof HttpError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  });
}

Deno.test("a try names one Pro look or one Pro style", () => {
  assert.deepEqual(unlockRequest(PRO_LOOK, undefined), { type: "template", id: PRO_LOOK });
  assert.deepEqual(unlockRequest(undefined, PRO_STYLE), { type: "style", id: PRO_STYLE });
  assert.deepEqual(unlockRequest(null, PRO_STYLE), { type: "style", id: PRO_STYLE }, "null is not named");
  for (const style of PRO_STYLES) assert.ok(isUnlockable({ type: "style", id: style }), style);
  for (const template of catalog.templates) {
    assert.equal(isUnlockable({ type: "template", id: template.id }), template.isPro, template.id);
  }
  assert.equal(itemField("template"), "template_id");
  assert.equal(itemField("style"), "style_id");
});

Deno.test("free looks, unknown ids and the other kind's ids can't be tried with an ad", () => {
  refused(() => unlockRequest(FREE_LOOK, undefined), 400, "not_unlockable");
  refused(() => unlockRequest("no-such-look", undefined), 400, "not_unlockable");
  refused(() => unlockRequest(undefined, "no-such-style"), 400, "not_unlockable");
  if (!templateRecipe(PRO_STYLE)) refused(() => unlockRequest(PRO_STYLE, undefined), 400, "not_unlockable");
  if (!PRO_STYLES.has(PRO_LOOK)) refused(() => unlockRequest(undefined, PRO_LOOK), 400, "not_unlockable");
});

Deno.test("exactly one id, as a short string", () => {
  refused(() => unlockRequest(PRO_LOOK, PRO_STYLE), 400, "bad_request");
  refused(() => unlockRequest(undefined, undefined), 400, "bad_request");
  refused(() => unlockRequest(null, null), 400, "bad_request");
  refused(() => unlockRequest(42, undefined), 400, "bad_request");
  refused(() => unlockRequest("", undefined), 400, "bad_request");
  refused(() => unlockRequest("x".repeat(101), undefined), 400, "bad_request");
  refused(() => unlockRequest(undefined, [PRO_STYLE]), 400, "bad_request");
});

Deno.test("a job asks for a try only for what Pro would unlock", () => {
  const pro = templateRecipe(PRO_LOOK);
  const free = templateRecipe(FREE_LOOK);
  assert.deepEqual(proItemsFor(true, PRO_STYLE, pro), [], "Pro needs none");
  assert.deepEqual(proItemsFor(false, undefined, free), [], "a free look needs none");
  assert.deepEqual(proItemsFor(false, "not-a-pro-style", undefined), [], "neither does a free style");
  assert.deepEqual(proItemsFor(false, undefined, pro), [{ type: "template", id: PRO_LOOK }]);
  assert.deepEqual(proItemsFor(false, PRO_STYLE, undefined), [{ type: "style", id: PRO_STYLE }]);
  assert.deepEqual(proItemsFor(false, PRO_STYLE, pro), [
    { type: "style", id: PRO_STYLE },
    { type: "template", id: PRO_LOOK },
  ], "the style first, as ai-image always checked");
});
