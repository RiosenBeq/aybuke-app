// deno test _shared/
import assert from "node:assert/strict";
import { HttpError } from "./http.ts";
import { DEFAULT_ENHANCE_MODE, ENHANCE_MODES, ENHANCE_SKIN_GUARD, enhanceMode, enhancePrompt } from "./enhance.ts";
import { evaluatePrompt } from "./policy.ts";
import { buildRequest, ENHANCE_PROMPT } from "./xai.ts";

const PHOTO = "data:image/jpeg;base64,/9j/4A==";

Deno.test("an app without modes gets the 1.0 Enhance, unchanged", () => {
  assert.equal(enhanceMode(undefined), "unblur");
  assert.equal(enhanceMode(null), DEFAULT_ENHANCE_MODE);
  assert.equal(
    enhancePrompt(),
    "Enhance this photo: make it sharper and more detailed, reduce blur and noise, restore faces naturally and gently improve the lighting. Keep real skin texture, freckles, moles, pores and blemishes; don't retouch or smooth the skin, and don't reshape the face or body. Keep the composition, colors, every person and their identity exactly the same.",
  );
  assert.equal(ENHANCE_PROMPT, enhancePrompt("unblur"));
});

Deno.test("every mode keeps the skin and identity guard and never asks for smoothing", () => {
  assert.deepEqual([...ENHANCE_MODES].sort(), ["hd", "low_light", "restore", "restore_color", "unblur"]);
  for (const id of ENHANCE_MODES) {
    const prompt = enhancePrompt(enhanceMode(id));
    assert.ok(prompt.includes(ENHANCE_SKIN_GUARD), id);
    assert.ok(prompt.includes("every person and their identity exactly the same"), id);
    assert.ok(!prompt.replace(ENHANCE_SKIN_GUARD, "").toLowerCase().includes("smooth"), id);
    assert.ok(evaluatePrompt(prompt, "magic_edit").allowed, id);
  }
});

Deno.test("an unknown mode or anything but a name is refused", () => {
  for (const raw of ["make my skin flawless", "UNBLUR", 3, {}, ["hd"]]) {
    assert.throws(() => enhanceMode(raw), (error: unknown) => error instanceof HttpError && error.status === 400);
  }
});

Deno.test("xAI gets the mode's instruction, never the request's own words", () => {
  // No env access in CI: the model names fall back to their defaults.
  const realGet = Deno.env.get;
  Deno.env.get = () => undefined;
  try {
    checkBuiltRequests();
  } finally {
    Deno.env.get = realGet;
  }
});

function checkBuiltRequests() {
  const request = buildRequest({
    operation: "enhance",
    prompt: "smooth my skin",
    enhanceMode: "low_light",
    numOutputs: 1,
    image: PHOTO,
    isPro: false,
  });
  assert.equal(request.path, "edits");
  assert.equal(request.body.prompt, enhancePrompt("low_light"));
  const old = buildRequest({ operation: "enhance", numOutputs: 1, image: PHOTO, isPro: false });
  assert.equal(old.body.prompt, ENHANCE_PROMPT);
}
