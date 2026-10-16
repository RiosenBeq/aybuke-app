// The daily caps the app shows, read from ad_reward_policy: daily_cap for the
// ads that pay a credit, unlock_daily_cap for the ones that unlock a Pro try.
// A failed read is unknown (null), never a number: the app keeps its own copy
// until a reply gives one, so an error can't report an old cap after the
// policy changed.
export interface AdCaps {
  credit: number | null;
  unlock: number | null;
}

export async function readCaps(
  call: () => PromiseLike<{ data: unknown; error: { message: string } | null }>,
): Promise<AdCaps> {
  const { data, error } = await call();
  if (error) {
    console.error("ad_reward_policy failed", error.message);
    return { credit: null, unlock: null };
  }
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null | undefined;
  const cap = (value: unknown) => typeof value === "number" ? value : null;
  return { credit: cap(row?.daily_cap), unlock: cap(row?.unlock_daily_cap) };
}
