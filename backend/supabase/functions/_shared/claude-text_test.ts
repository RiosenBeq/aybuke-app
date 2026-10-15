// deno test _shared/
// Claude's text help through the real SDK, every request answered by a mocked
// fetch: the request (text only, no thinking, low effort, the schema), the
// answers it accepts, and failures that come back short, without her text.
import assert from "node:assert/strict";
import { claudeAnswer, claudeError, hangingFetch, mockClaude, withoutEnv } from "./claude-mock.ts";
import {
  askForJson,
  buildTextRequest,
  type JsonTask,
  readJsonAnswer,
  type TextHelperConfig,
  textHelperConfig,
} from "./claude-text.ts";

const env = (values: Record<string, string>) => ({ get: (name: string) => values[name] });
const CONFIG: TextHelperConfig = { apiKey: "test-key", model: "claude-haiku-5-5" };
const SCHEMA = {
  type: "object",
  properties: { suggestions: { type: "array", items: { type: "string" } } },
  required: ["suggestions"],
  additionalProperties: false,
};
const TASK: JsonTask = { system: "You write ideas.", user: "Her words: a cozy café", schema: SCHEMA, maxTokens: 800 };

const ask = (fn: typeof fetch, deadlineMs = 2_000, maxRetries?: number) =>
  withoutEnv(() => askForJson(CONFIG, TASK, { deadlineMs, maxRetries, fetcher: fn }));

Deno.test("text help is on with ANTHROPIC_API_KEY; ANTHROPIC_ASSIST_MODEL picks the model", () => {
  assert.deepEqual(textHelperConfig(env({ ANTHROPIC_API_KEY: "key" })), { apiKey: "key", model: "claude-haiku-5-5" });
  assert.deepEqual(
    textHelperConfig(env({ ANTHROPIC_API_KEY: " key ", ANTHROPIC_ASSIST_MODEL: " claude-haiku-4-5 " })),
    { apiKey: "key", model: "claude-haiku-4-5" },
  );
  assert.equal(textHelperConfig(env({ ANTHROPIC_API_KEY: " " })), undefined);
  assert.equal(textHelperConfig(env({ ANTHROPIC_ASSIST_MODEL: "claude-haiku-5-5" })), undefined);
});

Deno.test("the request: text only, thinking off, low effort, the JSON schema, no sampling settings", () => {
  const body = buildTextRequest("claude-haiku-5-5", TASK);
  assert.equal(body.model, "claude-haiku-5-5");
  assert.equal(body.max_tokens, 800);
  assert.deepEqual(body.thinking, { type: "disabled" });
  assert.deepEqual(body.output_config, { effort: "low", format: { type: "json_schema", schema: SCHEMA } });
  assert.equal(body.system, "You write ideas.");
  assert.deepEqual(body.messages, [{ role: "user", content: "Her words: a cozy café" }]);
  assert.equal("temperature" in body, false);
});

Deno.test("an answer is one text block of JSON after a normal end", async () => {
  const api = mockClaude(() => claudeAnswer({ suggestions: ["A cat café at dusk"] }));
  assert.deepEqual(await ask(api.fn), { ok: true, value: { suggestions: ["A cat café at dusk"] } });
  assert.equal(api.calls.length, 1);
  const call = api.calls[0];
  assert.equal(call.url, "https://api.anthropic.com/v1/messages");
  assert.equal(call.headers.get("x-api-key"), "test-key");
  assert.deepEqual(call.body.thinking, { type: "disabled" });
  assert.equal(call.body.output_config.effort, "low");
  assert.deepEqual(call.body.messages, [{ role: "user", content: "Her words: a cozy café" }]);
  // Nothing in the request is an image.
  assert.ok(!JSON.stringify(call.body).includes('"image"'));
});

Deno.test("a refusal, a cut-off or anything but one JSON text block is a failure", () => {
  const text = (value: string) => ({ type: "text" as const, text: value, citations: null });
  const cases: [Parameters<typeof readJsonAnswer>[0], string][] = [
    [{ stop_reason: "refusal", content: [] }, "refused"],
    [{ stop_reason: "max_tokens", content: [text('{"suggestions": ["a')] }, "cut off"],
    [{ stop_reason: "pause_turn", content: [] }, "stopped: pause_turn"],
    [{ stop_reason: "end_turn", content: [] }, "no content"],
    [{ stop_reason: "end_turn", content: [text("{}"), text("{}")] }, "unexpected content"],
    [{ stop_reason: "end_turn", content: [text("Here you go!")] }, "not JSON"],
  ];
  for (const [message, detail] of cases) assert.deepEqual(readJsonAnswer(message), { ok: false, detail });
});

Deno.test("HTTP errors, timeouts and dropped connections fail short, retried once when it can help", async () => {
  const busy = mockClaude(() => claudeError(529, "overloaded_error", { "retry-after-ms": "1" }));
  assert.deepEqual(await ask(busy.fn), { ok: false, detail: "HTTP 529 overloaded_error" });
  assert.equal(busy.calls.length, 2, "one retry");

  const recovered = mockClaude(() =>
    recovered.calls.length === 1 ? claudeError(500, "api_error", { "retry-after-ms": "1" }) : claudeAnswer({})
  );
  assert.deepEqual(await ask(recovered.fn), { ok: true, value: {} });

  const rejected = mockClaude(() => claudeError(400, "invalid_request_error"));
  assert.deepEqual(await ask(rejected.fn), { ok: false, detail: "HTTP 400 invalid_request_error" });
  assert.equal(rejected.calls.length, 1, "no retry for a 400");

  const started = Date.now();
  const timedOut = await ask(hangingFetch, 100, 0);
  assert.ok(!timedOut.ok && ["timeout", "deadline"].includes(timedOut.detail), JSON.stringify(timedOut));
  assert.ok(Date.now() - started < 3_000, "the deadline holds");

  const down = (() => Promise.reject(new TypeError("network down"))) as typeof fetch;
  assert.deepEqual(await ask(down, 2_000, 0), { ok: false, detail: "connection failed" });

  // A long Retry-After never stretches the deadline.
  const limited = mockClaude(() => claudeError(429, "rate_limit_error", { "retry-after": "3600" }));
  const before = Date.now();
  assert.deepEqual(await ask(limited.fn, 150), { ok: false, detail: "deadline" });
  assert.ok(Date.now() - before < 3_000);
});

Deno.test("no failure carries the key or her text", async () => {
  const fetchers = [
    mockClaude(() => claudeError(401, "authentication_error")).fn,
    mockClaude(() => new Response("test-key a cozy café", { status: 400 })).fn,
    (() => Promise.reject(new Error("test-key a cozy café"))) as typeof fetch,
  ];
  for (const fn of fetchers) {
    const answer = await ask(fn, 2_000, 0);
    assert.ok(!answer.ok);
    const shown = JSON.stringify(answer);
    assert.ok(!shown.includes("test-key") && !shown.includes("cozy"), shown);
  }
});
