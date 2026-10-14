// deno test _shared/
import assert from "node:assert/strict";
import { ADMISSION_MESSAGES, admissionError } from "./admission.ts";
import { errorResponse } from "./http.ts";

Deno.test("refusals become the error contract the app decodes", async () => {
  const until = "2026-10-15T12:00:00.000Z";
  const response = errorResponse(
    admissionError({ ok: false, code: "cooldown", status: 429, retry_after: 3600, until }),
  );
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "3600");
  const body = await response.json() as { error: Record<string, unknown> };
  assert.deepEqual(body.error, { until, code: "cooldown", message: ADMISSION_MESSAGES.cooldown, retry_after: 3600 });
});

Deno.test("each code keeps its status, balance and message", async () => {
  const cases: [Record<string, unknown>, number, string][] = [
    [{ ok: false, code: "insufficient_credits", status: 402, credits_remaining: 0 }, 402, "insufficient_credits"],
    [{ ok: false, code: "app_transaction_required", status: 428 }, 428, "app_transaction_required"],
    [{ ok: false, code: "install_blocked", status: 403 }, 403, "install_blocked"],
    [{ ok: false, code: "ai_paused", status: 503, retry_after: 600 }, 503, "ai_paused"],
    [{ ok: false, code: "retry_limit", status: 409 }, 409, "retry_limit"],
    [{ ok: false, code: "usage_limit", status: 429, retry_after: 1200 }, 429, "usage_limit"],
  ];
  for (const [result, status, code] of cases) {
    const response = errorResponse(admissionError(result as { ok: boolean }));
    assert.equal(response.status, status, code);
    const body = await response.json() as { error: { code: string; message: string; credits_remaining?: number } };
    assert.equal(body.error.code, code);
    assert.ok(body.error.message.length > 0);
    if (code === "insufficient_credits") assert.equal(body.error.credits_remaining, 0);
  }
  const blocked = await errorResponse(
    admissionError({ ok: false, code: "content_blocked", status: 422 }, "Not this one."),
  )
    .json() as { error: { message: string } };
  assert.equal(blocked.error.message, "Not this one.", "the policy's own message");
  // Kind words, never blame: the users are teens.
  for (const message of Object.values(ADMISSION_MESSAGES)) {
    assert.ok(!/abuse|violat|banned|suspend|fraud/i.test(message), message);
  }
});
