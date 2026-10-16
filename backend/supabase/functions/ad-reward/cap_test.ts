// deno test ad-reward/
// The daily caps the app shows come from ad_reward_policy. A failed read is
// unknown (null), never the old default, so a retuned policy can't be
// contradicted by a stale number.
import assert from "node:assert/strict";
import { readCaps } from "./cap.ts";

const replies = (data: unknown) => () => Promise.resolve({ data, error: null });
const failed = () => Promise.resolve({ data: null, error: { message: "connection reset" } });

Deno.test("a failed policy read is unknown, not the default", async () => {
  assert.deepEqual(await readCaps(failed), { credit: null, unlock: null });
});

Deno.test("the caps are the policy's, even when it's retuned", async () => {
  const policy = { daily_cap: 2, credits: 1, token_ttl: "00:30:00", unlock_daily_cap: 1, unlock_ttl: "00:30:00" };
  assert.deepEqual(await readCaps(replies([policy])), { credit: 2, unlock: 1 });
  assert.deepEqual(await readCaps(replies([{ ...policy, daily_cap: 5, unlock_daily_cap: 3 }])), {
    credit: 5,
    unlock: 3,
  });
  assert.deepEqual(await readCaps(replies({ daily_cap: 1, unlock_daily_cap: 2 })), { credit: 1, unlock: 2 });
});

Deno.test("a policy from before the tries has no unlock cap yet", async () => {
  assert.deepEqual(await readCaps(replies([{ daily_cap: 2, credits: 1, token_ttl: "00:30:00" }])), {
    credit: 2,
    unlock: null,
  });
});

Deno.test("an empty or odd reply is unknown", async () => {
  assert.deepEqual(await readCaps(replies([])), { credit: null, unlock: null });
  assert.deepEqual(await readCaps(replies(null)), { credit: null, unlock: null });
  assert.deepEqual(await readCaps(replies({ daily_cap: "2", unlock_daily_cap: "1" })), { credit: null, unlock: null });
});
