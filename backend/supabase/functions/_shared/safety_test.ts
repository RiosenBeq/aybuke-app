// deno test _shared/
import assert from "node:assert/strict";
import { buildRequest, classifyImages, parseVerdict, safetyModel, XAI_CHAT_URL } from "./safety.ts";

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

const options = (fn: typeof fetch) => ({ model: "grok-vision-test", apiKey: "test-key", fetcher: fn });
const image = "data:image/jpeg;base64,AAAA";

Deno.test("off unless XAI_SAFETY_MODEL is set", () => {
  assert.equal(safetyModel(env({})), undefined);
  assert.equal(safetyModel(env({ XAI_SAFETY_MODEL: "  " })), undefined);
  assert.equal(safetyModel(env({ XAI_SAFETY_MODEL: "grok-4-fast" })), "grok-4-fast");
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
});
