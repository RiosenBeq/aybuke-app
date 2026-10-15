// deno test _shared/
// What ai-image reports to the safety check's circuit breaker, with the
// database stubbed (the breaker itself: supabase/tests/safety_breaker_test.sql).
import assert from "node:assert/strict";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { noteSafetyCheckError } from "./safety-breaker.ts";
import type { SafetyVerdict } from "./safety.ts";

type Db = Pick<SupabaseClient, "rpc">;

/** A database whose rpc() answers `answer` and remembers each call. */
function database(answer: () => Promise<{ data: unknown; error: { message: string } | null }>) {
  const calls: { name: string; args: unknown }[] = [];
  const db = {
    rpc: (name: string, args: unknown) => {
      calls.push({ name, args });
      return { abortSignal: () => answer() };
    },
  } as unknown as Db;
  return { db, calls };
}

const failed = (detail: string): SafetyVerdict => ({ ok: false, reason: "check_failed", detail });

async function quietly<T>(run: () => Promise<T>): Promise<T> {
  const [warn, error] = [console.warn, console.error];
  console.warn = () => {};
  console.error = () => {};
  try {
    return await run();
  } finally {
    console.warn = warn;
    console.error = error;
  }
}

Deno.test("a check that couldn't run is reported, with its short reason", async () => {
  const { db, calls } = database(() => Promise.resolve({ data: null, error: null }));
  assert.equal(await noteSafetyCheckError(db, failed("HTTP 529 overloaded_error"), "result"), undefined);
  assert.deepEqual(calls, [{ name: "note_safety_check_error", args: { p_detail: "HTTP 529 overloaded_error" } }]);
});

Deno.test("the report that trips the breaker returns when the pause ends", async () => {
  const until = "2026-10-15T12:05:00+00:00";
  const { db } = database(() => Promise.resolve({ data: until, error: null }));
  assert.equal(await quietly(() => noteSafetyCheckError(db, failed("timeout"), "result")), until);
});

Deno.test("verdicts, refusals and images the model can't take are no outage", async () => {
  const { db, calls } = database(() => Promise.resolve({ data: null, error: null }));
  for (
    const verdict of [
      { ok: true },
      { ok: false, reason: "flagged", categories: ["nudity"] },
      failed("refused"),
      failed("unsupported image type"),
      failed("image too large"),
    ] as SafetyVerdict[]
  ) {
    assert.equal(await noteSafetyCheckError(db, verdict, "result"), undefined);
  }
  assert.equal(calls.length, 0);
});

Deno.test("a photo check that couldn't run is never reported: one sender's broken files can't pause AI", async () => {
  const { db, calls } = database(() => Promise.resolve({ data: "2026-10-15T12:05:00+00:00", error: null }));
  for (const detail of ["HTTP 400 invalid_request_error", "timeout", "deadline", "HTTP 529 overloaded_error"]) {
    assert.equal(await noteSafetyCheckError(db, failed(detail), "photo"), undefined, detail);
  }
  assert.equal(calls.length, 0);
});

Deno.test("a report that fails is logged, never thrown", async () => {
  const refused = database(() => Promise.resolve({ data: null, error: { message: "permission denied" } }));
  assert.equal(await quietly(() => noteSafetyCheckError(refused.db, failed("timeout"), "result")), undefined);
  const down = database(() => Promise.reject(new Error("db down")));
  assert.equal(await quietly(() => noteSafetyCheckError(down.db, failed("timeout"), "result")), undefined);
});
