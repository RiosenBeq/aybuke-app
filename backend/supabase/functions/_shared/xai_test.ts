// deno test _shared/
// xAI refusing a job for billing (out of credit, over the spending limit) is
// its own outcome, provider_billing, with fetch stubbed; busy, moderated and
// failed answers map as before (moderation_test.ts).
import assert from "node:assert/strict";
import type { JobInput } from "./fal.ts";
import { generate, isBillingError, mapError } from "./xai.ts";

const INPUT: JobInput = {
  operation: "magic_edit",
  prompt: "give me pink hair",
  numOutputs: 1,
  image: "data:image/jpeg;base64,/9j/4A==",
  isPro: false,
};

/** Runs `body` with an xAI key and a stubbed xAI that answers `status` and `text`. */
async function withXAI(status: number, text: string, body: (calls: string[]) => Promise<void>) {
  const realGet = Deno.env.get;
  const realFetch = globalThis.fetch;
  const realError = console.error;
  const calls: string[] = [];
  Deno.env.get = (name: string) => (name === "XAI_API_KEY" ? "xai-test-key" : undefined);
  globalThis.fetch = ((input: string | URL | Request) => {
    calls.push(String(input));
    return Promise.resolve(new Response(text, { status }));
  }) as typeof fetch;
  console.error = () => {};
  try {
    await body(calls);
  } finally {
    Deno.env.get = realGet;
    globalThis.fetch = realFetch;
    console.error = realError;
  }
}

const OUT_OF_CREDIT =
  '{"code":"The caller does not have permission to execute the specified operation","error":"Your team has either used all available credits or reached its monthly spending limit. To continue making API requests, please purchase more credits or raise your spending limit."}';

Deno.test("an xAI team out of credit or over its spending limit is provider_billing, and refunded", async () => {
  for (const [status, text] of [[402, "Payment Required"], [403, OUT_OF_CREDIT], [429, OUT_OF_CREDIT]] as const) {
    await withXAI(status, text, async (calls) => {
      const outcome = await generate(INPUT);
      assert.equal(calls[0], "https://api.x.ai/v1/images/edits");
      assert.ok(!outcome.ok && outcome.code === "provider_billing", `${status}`);
      assert.ok(!outcome.ok && outcome.message.includes("refunded"));
    });
  }
});

Deno.test("busy, moderated and other refusals keep their codes", async () => {
  await withXAI(429, '{"error":"Too many requests: rate limit exceeded"}', async () => {
    const outcome = await generate(INPUT);
    assert.ok(!outcome.ok && outcome.code === "provider_busy");
  });
  await withXAI(403, '{"code":"imagine:content-moderated","error":"Generated image rejected"}', async () => {
    const outcome = await generate(INPUT);
    assert.ok(!outcome.ok && outcome.code === "content_blocked");
  });
  await withXAI(403, '{"error":"Incorrect API key provided"}', async () => {
    const outcome = await generate(INPUT);
    assert.ok(!outcome.ok && outcome.code === "provider_failed");
  });
});

Deno.test("isBillingError: 402 always, 403 and 429 only when they say so", () => {
  assert.ok(isBillingError(402, ""));
  assert.ok(isBillingError(403, "Your credit balance is too low"));
  assert.ok(isBillingError(429, "monthly spending limit reached"));
  assert.ok(isBillingError(403, "Billing: add a payment method"));
  assert.ok(!isBillingError(429, "rate limited"));
  assert.ok(!isBillingError(403, "invalid credentials"));
  assert.ok(!isBillingError(500, "out of credits"));
  const billing = mapError(402, '{"error":"content moderation unavailable"}');
  assert.ok(!billing.ok && billing.code === "provider_billing", "a 402 is billing whatever it says");
});
