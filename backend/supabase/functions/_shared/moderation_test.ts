// deno test _shared/
import assert from "node:assert/strict";
import { checkOutputs, FAL_NSFW_URL, outputCheck } from "./moderation.ts";
import { mapError, parseOutputs } from "./xai.ts";

const env = (values: Record<string, string>) => ({ get: (name: string) => values[name] });
const image = { base64: "/9j/4AAQ", content_type: "image/jpeg" };

/** A fetch that answers every call with `answer` and remembers the requests. */
function fakeFetch(answer: () => Response | Promise<Response>) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fetcher = ((input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    return Promise.resolve(answer());
  }) as typeof fetch;
  return { fetcher, calls };
}

Deno.test("the check in force is fal.ai with FAL_KEY, otherwise xAI's verdict, never none", () => {
  assert.equal(outputCheck(env({ FAL_KEY: "key" })), "fal");
  assert.equal(outputCheck(env({ FAL_KEY: "key", OUTPUT_MODERATION: "off" })), "fal");
  assert.equal(outputCheck(env({})), "xai");
  assert.equal(outputCheck(env({ OUTPUT_MODERATION: "off" })), "xai");
});

Deno.test("xAI's verdict: only results that came through xAI's moderation pass", async () => {
  assert.deepEqual(await checkOutputs([image], "xai", { check: "xai" }), { ok: true, check: "xai" });
  // A fal result has no xAI verdict: without FAL_KEY nothing may vouch for it.
  assert.deepEqual(await checkOutputs([{ url: "https://cdn/a.jpg" }], undefined, { check: "xai" }), {
    ok: false,
    check: "xai",
    reason: "check_failed",
  });
  assert.equal((await checkOutputs([], "xai", { check: "xai" })).ok, false);
});

Deno.test("fal.ai's classifier passes clean results and blocks flagged ones", async () => {
  const clean = fakeFetch(() => Response.json({ has_nsfw_concepts: [false, false] }));
  const verdict = await checkOutputs([image, { url: "https://cdn/b.jpg" }], "xai", {
    check: "fal",
    falKey: "key",
    fetcher: clean.fetcher,
  });
  assert.deepEqual(verdict, { ok: true, check: "fal" });
  assert.equal(clean.calls.length, 1);
  assert.equal(clean.calls[0].url, FAL_NSFW_URL);
  const sent = JSON.parse(String(clean.calls[0].init?.body)) as { image_urls: string[] };
  assert.deepEqual(sent.image_urls, ["data:image/jpeg;base64,/9j/4AAQ", "https://cdn/b.jpg"]);
  assert.equal((clean.calls[0].init?.headers as Record<string, string>)["X-Fal-Store-IO"], "0");

  // xAI passing the image doesn't skip the independent check.
  const flagged = fakeFetch(() => Response.json({ has_nsfw_concepts: [false, true] }));
  assert.deepEqual(
    await checkOutputs([image, image], "xai", { check: "fal", falKey: "key", fetcher: flagged.fetcher }),
    { ok: false, check: "fal", reason: "flagged" },
  );
});

Deno.test("fal.ai's classifier fails closed", async () => {
  const failures: [string, () => Response | Promise<Response>][] = [
    ["server error", () => new Response("busy", { status: 500 })],
    ["rate limit", () => new Response("slow down", { status: 429 })],
    ["not JSON", () => new Response("<html>")],
    ["no verdict", () => Response.json({})],
    ["a verdict per image missing", () => Response.json({ has_nsfw_concepts: [false] })],
    ["not booleans", () => Response.json({ has_nsfw_concepts: ["false", "false"] })],
    ["network down", () => Promise.reject(new TypeError("error sending request"))],
  ];
  for (const [name, answer] of failures) {
    const { fetcher } = fakeFetch(answer);
    const verdict = await checkOutputs([image, image], undefined, { check: "fal", falKey: "key", fetcher });
    assert.deepEqual(verdict, { ok: false, check: "fal", reason: "check_failed" }, name);
  }
  const unused = fakeFetch(() => Response.json({ has_nsfw_concepts: [false] }));
  assert.deepEqual(
    await checkOutputs([image], undefined, { check: "fal", falKey: "", fetcher: unused.fetcher }),
    { ok: false, check: "fal", reason: "check_failed" },
    "no key, no check",
  );
  assert.equal(unused.calls.length, 0);
});

Deno.test("xAI results are delivered only when every image passed its moderation", () => {
  const kept = parseOutputs(JSON.stringify({ data: [{ b64_json: "/9j/4A==", respect_moderation: true }] }));
  assert.deepEqual(kept, {
    ok: true,
    moderatedBy: "xai",
    outputs: [{ base64: "/9j/4A==", content_type: "image/jpeg" }],
  });
  const png = parseOutputs(JSON.stringify({ data: [{ b64_json: "iVBORw0KGgo=", mime_type: "image/png" }] }));
  assert.ok(png.ok && png.outputs[0].content_type === "image/png", "the verdict field may be absent on a clean image");

  const blocked = { ok: false, code: "content_blocked" };
  const filtered = parseOutputs(JSON.stringify({ data: [{ b64_json: null, respect_moderation: false }] }));
  assert.deepEqual({ ok: filtered.ok, code: !filtered.ok && filtered.code }, blocked);
  const oneOfTwo = parseOutputs(
    JSON.stringify({ data: [{ b64_json: "/9j/4A==" }, { b64_json: "/9j/4B==", respect_moderation: false }] }),
    2,
  );
  assert.deepEqual({ ok: oneOfTwo.ok, code: !oneOfTwo.ok && oneOfTwo.code }, blocked, "never delivered in part");
  const withheld = parseOutputs(JSON.stringify({ data: [{ b64_json: "/9j/4A==" }, { url: null, b64_json: null }] }), 2);
  assert.deepEqual({ ok: withheld.ok, code: !withheld.ok && withheld.code }, blocked, "a withheld image blocks");
  const short = parseOutputs(JSON.stringify({ data: [{ b64_json: "/9j/4A==" }] }), 4);
  assert.deepEqual({ ok: short.ok, code: !short.ok && short.code }, blocked, "missing images block");

  for (const text of ['{"data":[]}', "{}", "not json"]) {
    const empty = parseOutputs(text);
    assert.ok(!empty.ok && empty.code === "empty_result", text);
  }
});

Deno.test("xAI's moderation errors are reported as blocked", () => {
  const moderated = mapError(400, '{"code":"imagine:content-moderated","error":"Generated image rejected"}');
  assert.ok(!moderated.ok && moderated.code === "content_blocked");
  const busy = mapError(429, "rate limited");
  assert.ok(!busy.ok && busy.code === "provider_busy");
  const failed = mapError(500, "internal");
  assert.ok(!failed.ok && failed.code === "provider_failed");
});
