// The daily cap the app shows, read from ad_reward_policy. A failed read is
// unknown (null), never a number: the app keeps its own copy until a reply
// gives one, so an error can't report an old cap after the policy changed.
export async function readDailyCap(
  call: () => PromiseLike<{ data: unknown; error: { message: string } | null }>,
): Promise<number | null> {
  const { data, error } = await call();
  if (error) {
    console.error("ad_reward_policy failed", error.message);
    return null;
  }
  const row = (Array.isArray(data) ? data[0] : data) as { daily_cap?: unknown } | null | undefined;
  return typeof row?.daily_cap === "number" ? row.daily_cap : null;
}
