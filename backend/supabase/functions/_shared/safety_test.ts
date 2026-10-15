// deno test _shared/
import assert from "node:assert/strict";
import {
  buildRequest,
  CATEGORIES,
  classifyImages,
  isServiceFailure,
  parseVerdict,
  RESULT_CATEGORIES,
  resultCountsAsStrike,
  safetyModel,
  safetyProvider,
  systemPrompt,
  XAI_CHAT_URL,
} from "./safety.ts";

const env = (values: Record<string, string>) => ({ get: (name: string) => values[name] });
const answer = (content: unknown, extra: Record<string, unknown> = {}) => ({
  choices: [{ message: { content: typeof content === "string" ? content : JSON.stringify(content), ...extra } }],
});

function fetcher(respond: (body: Record<string, unknown>) => Response | Promise<Response>) {
  const calls: { url: string; body: Record<string, unknown>; auth: string | null }[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? "{}"));
    calls.push({ url: String(input), body, auth: new Headers(init?.headers).get("Authorization") });
    return await respond(body);
  }) as typeof fetch;
  return { fn, calls };
}

const options = (fn: typeof fetch) => ({
  provider: "xai" as const,
  model: "grok-vision-test",
  apiKey: "test-key",
  fetcher: fn,
});
const image = "data:image/jpeg;base64,AAAA";

Deno.test("without ANTHROPIC_API_KEY, the xAI check is off unless XAI_SAFETY_MODEL is set", () => {
  assert.equal(safetyModel(env({})), undefined);
  assert.equal(safetyModel(env({ XAI_SAFETY_MODEL: "  " })), undefined);
  assert.equal(safetyModel(env({ XAI_SAFETY_MODEL: "grok-4-fast" })), "grok-4-fast");
  assert.equal(safetyProvider(env({ XAI_SAFETY_MODEL: "grok-4-fast" })), "xai");
});

Deno.test("the request: one image, low detail, a strict JSON schema", () => {
  const body = buildRequest("grok-vision-test", image, "photo") as {
    model: string;
    temperature: number;
    messages: { role: string; content: unknown }[];
    response_format: { type: string; json_schema: { strict: boolean } };
  };
  assert.equal(body.model, "grok-vision-test");
  assert.equal(body.temperature, 0);
  assert.equal(body.messages[0].role, "system");
  const parts = body.messages[1].content as { type: string; image_url?: { url: string; detail: string } }[];
  assert.equal(parts[0].image_url?.url, image);
  assert.equal(parts[0].image_url?.detail, "low");
  assert.equal(body.response_format.type, "json_schema");
  assert.ok(body.response_format.json_schema.strict);
});

Deno.test("clean images pass; a flag or a category blocks", async () => {
  const clean = fetcher(() => Response.json(answer({ flagged: false, categories: [] })));
  assert.deepEqual(await classifyImages([image, image], "result", options(clean.fn)), { ok: true });
  assert.equal(clean.calls.length, 2, "every image is checked");
  assert.equal(clean.calls[0].url, XAI_CHAT_URL);
  assert.equal(clean.calls[0].auth, "Bearer test-key");

  const flagged = fetcher((body) => {
    const parts = (body.messages as { content: { image_url?: { url: string } }[] }[])[1].content;
    const second = parts[0].image_url?.url.endsWith("BBBB");
    return Response.json(
      answer(second ? { flagged: true, categories: ["nudity"] } : { flagged: false, categories: [] }),
    );
  });
  assert.deepEqual(await classifyImages([image, "data:image/jpeg;base64,BBBB"], "result", options(flagged.fn)), {
    ok: false,
    reason: "flagged",
    categories: ["nudity"],
  });
  // A contradiction (a category without the flag) blocks too.
  assert.deepEqual(parseVerdict(answer({ flagged: false, categories: ["hate"] })), {
    ok: false,
    reason: "flagged",
    categories: ["hate"],
  });
});

Deno.test("categories are read case-insensitively and come back lowercase", () => {
  assert.deepEqual(parseVerdict(answer({ flagged: true, categories: ["Nudity"] })), {
    ok: false,
    reason: "flagged",
    categories: ["nudity"],
  });
  // A category alone still flags, whatever its case, and one name is one category.
  assert.deepEqual(parseVerdict(answer({ flagged: false, categories: ["SELF_HARM", "self_harm", "Hate"] })), {
    ok: false,
    reason: "flagged",
    categories: ["self_harm", "hate"],
  });
  // An unknown name fails closed in any case.
  assert.deepEqual(parseVerdict(answer({ flagged: true, categories: ["Nudity", "Bogus"] })), {
    ok: false,
    reason: "check_failed",
    detail: "unexpected category",
  });
});

Deno.test("fails closed: errors, timeouts, refusals and odd answers block", async () => {
  const failed = async (fn: typeof fetch) => {
    const verdict = await classifyImages([image], "photo", { ...options(fn), timeoutMs: 50 });
    assert.ok(!verdict.ok && verdict.reason === "check_failed", JSON.stringify(verdict));
  };
  await failed(fetcher(() => new Response("busy", { status: 503 })).fn);
  await failed(fetcher(() => Response.json(answer("I can't help with that."))).fn);
  await failed(fetcher(() => Response.json(answer({ verdict: "fine" }))).fn);
  await failed(fetcher(() => Response.json(answer({ flagged: "no", categories: [] }))).fn);
  await failed(fetcher(() => Response.json(answer(null, { content: null, refusal: "no" }))).fn);
  await failed(fetcher(() => Response.json({ choices: [] })).fn);
  await failed(fetcher(() => new Response("not json")).fn);
  await failed((() => Promise.reject(new TypeError("network down"))) as typeof fetch);
  await failed(
    ((_: unknown, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new DOMException("timed out", "TimeoutError")));
      })) as typeof fetch,
  );
  const none = await classifyImages([], "result", options(fetcher(() => Response.json(answer({}))).fn));
  assert.ok(!none.ok && none.reason === "check_failed", "nothing to check isn't a pass");
  // A refusal is a failed check (refunded, no strike), logged as exactly "refused".
  assert.deepEqual(parseVerdict(answer(null, { content: null, refusal: "I can't look at this." })), {
    ok: false,
    reason: "check_failed",
    detail: "refused",
  });
});

Deno.test("an answer outside the schema fails closed, whatever flagged says", () => {
  assert.deepEqual(parseVerdict(answer({ flagged: false, categories: ["bogus"] })), {
    ok: false,
    reason: "check_failed",
    detail: "unexpected category",
  });
  assert.deepEqual(parseVerdict(answer({ flagged: true, categories: ["bogus"] })), {
    ok: false,
    reason: "check_failed",
    detail: "unexpected category",
  });
  assert.deepEqual(parseVerdict(answer({ flagged: false, categories: [], note: "looks fine" })), {
    ok: false,
    reason: "check_failed",
    detail: "unexpected field",
  });
  assert.deepEqual(parseVerdict(answer([])), { ok: false, reason: "check_failed", detail: "unexpected shape" });
  assert.deepEqual(parseVerdict(answer("true")), { ok: false, reason: "check_failed", detail: "unexpected shape" });
});

Deno.test("the xAI request asks about substances and weapons on results only", () => {
  const schemaEnum = (subject: "photo" | "result") => {
    const body = buildRequest("grok-vision-test", image, subject) as {
      messages: { content: unknown }[];
      response_format: { json_schema: { schema: { properties: { categories: { items: { enum: string[] } } } } } };
    };
    assert.equal(body.messages[0].content, systemPrompt(subject));
    return body.response_format.json_schema.schema.properties.categories.items.enum;
  };
  assert.deepEqual(schemaEnum("photo"), [...CATEGORIES]);
  assert.deepEqual(schemaEnum("result"), [...CATEGORIES, ...RESULT_CATEGORIES]);
  assert.ok(systemPrompt("result").includes("substances (alcohol, tobacco, vaping or drugs"));
  assert.ok(!systemPrompt("photo").includes("alcohol") && !systemPrompt("photo").includes("weapons"));

  assert.deepEqual(parseVerdict(answer({ flagged: true, categories: ["weapons"] }), "result"), {
    ok: false,
    reason: "flagged",
    categories: ["weapons"],
  });
  assert.deepEqual(parseVerdict(answer({ flagged: true, categories: ["substances"] }), "photo"), {
    ok: false,
    reason: "check_failed",
    detail: "unexpected category",
  });
  assert.deepEqual(parseVerdict(answer({ flagged: false, categories: [] }), "photo"), { ok: true });
});

Deno.test("a result flagged only for substances or weapons in an edit of her photo is no strike", () => {
  // Creations: every flag is a strike.
  assert.ok(resultCountsAsStrike(["substances"], false));
  assert.ok(resultCountsAsStrike(["weapons"], false));
  // Edits of her photo: the drink may be hers, so blocked and refunded without a strike.
  assert.ok(!resultCountsAsStrike(["substances"], true));
  assert.ok(!resultCountsAsStrike(["substances", "weapons"], true));
  // Anything else is a strike as before, also next to them.
  assert.ok(resultCountsAsStrike(["nudity"], true));
  assert.ok(resultCountsAsStrike(["weapons", "graphic_violence"], true));
  assert.ok(resultCountsAsStrike([], true), "a flag without a category stays a strike");
});

Deno.test("only checks that couldn't run count as outages", () => {
  const failed = (detail: string) => ({ ok: false as const, reason: "check_failed" as const, detail });
  for (
    const detail of [
      "timeout",
      "deadline",
      "connection failed",
      "HTTP 529 overloaded_error",
      "HTTP 401 authentication_error",
      "not JSON",
      "cut off",
      "ANTHROPIC_API_KEY is not set",
    ]
  ) {
    assert.ok(isServiceFailure(failed(detail)), detail);
  }
  for (
    const detail of ["refused", "unsupported image type", "image too large", "bad base64", "not an image", "no images"]
  ) {
    assert.ok(!isServiceFailure(failed(detail)), detail);
  }
  assert.ok(!isServiceFailure({ ok: true }));
  assert.ok(!isServiceFailure({ ok: false, reason: "flagged", categories: ["nudity"] }));
});
