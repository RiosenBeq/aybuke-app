// deno test ad-reward/
// The daily cap the app shows comes from ad_reward_policy. A failed read is
// unknown (null), never the old default, so a retuned policy can't be
// contradicted by a stale number.
import assert from "node:assert/strict";
import { readDailyCap } from "./cap.ts";

const replies = (data: unknown) => () => Promise.resolve({ data, error: null });
const failed = () => Promise.resolve({ data: null, error: { message: "connection reset" } });

Deno.test("a failed policy read is unknown, not the default", async () => {
  assert.equal(await readDailyCap(failed), null);
});

Deno.test("the cap is the policy's, even when it's retuned", async () => {
  assert.equal(await readDailyCap(replies([{ daily_cap: 2, credits: 1, token_ttl: "00:30:00" }])), 2);
  assert.equal(await readDailyCap(replies([{ daily_cap: 5, credits: 1, token_ttl: "00:30:00" }])), 5);
  assert.equal(await readDailyCap(replies({ daily_cap: 1 })), 1);
});

Deno.test("an empty or odd reply is unknown", async () => {
  assert.equal(await readDailyCap(replies([])), null);
  assert.equal(await readDailyCap(replies(null)), null);
  assert.equal(await readDailyCap(replies({ daily_cap: "2" })), null);
});
