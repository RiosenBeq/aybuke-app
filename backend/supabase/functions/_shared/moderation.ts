// The output safety check every result passes before the app may download it.
// Exactly one check is always in force, and it fails closed: a result is
// delivered only after the check has run and passed; a flag, an error, a
// timeout or an answer we can't read blocks the result, and the job is
// refunded. There is no setting that turns it off.
//
//   "xai"  xAI's own moderation of each generated image (the default with
//          xAI and no FAL_KEY): xAI withholds the image data of any image it
//          filters, and xai.parseOutputs() blocks the whole job when it does.
//   "fal"  fal.ai's NSFW classifier, an alternative that is off unless FAL_KEY
//          is set; AI_PROVIDER=fal alone doesn't switch it on.
//
// The independent check is safety.ts, not this one: with ANTHROPIC_API_KEY set,
// Claude also looks at the photo before an edit and at every result, after
// this check has passed and with the same fail-closed rules. FAL_KEY stays
// unset: fal.ai would see results, so setting it needs fal.ai listed in the
// app's consent sheet (ios/App/Resources/AppConfig.json aiProcessors) and the
// privacy policies first. Part of the documented safeguards for EU AI Act
// Art. 5(1)(ba) (from 2 Dec 2026).
import type { Output } from "./fal.ts";

export type OutputCheck = "fal" | "xai";

export type Verdict =
  | { ok: true; check: OutputCheck }
  | { ok: false; check: OutputCheck; reason: "flagged" | "check_failed" };

interface Env {
  get(name: string): string | undefined;
}

export const FAL_NSFW_URL = "https://fal.run/fal-ai/x-ailab/nsfw";
const FAL_TIMEOUT_MS = 30_000;

/** The check in force: fal.ai's classifier with FAL_KEY, otherwise xAI's verdict. */
export function outputCheck(env: Env = Deno.env): OutputCheck {
  return env.get("FAL_KEY") ? "fal" : "xai";
}

export interface CheckOptions {
  /** Defaults to `outputCheck()`. */
  check?: OutputCheck;
  /** Defaults to the FAL_KEY secret. */
  falKey?: string;
  fetcher?: typeof fetch;
}

/**
 * Runs the check in force on a job's results. `moderatedBy` says which
 * provider already passed them through its own moderation (`"xai"` for an
 * xAI result that kept every image). Never throws.
 */
export async function checkOutputs(
  outputs: Output[],
  moderatedBy: OutputCheck | undefined,
  options: CheckOptions = {},
): Promise<Verdict> {
  const check = options.check ?? outputCheck();
  if (outputs.length === 0) return { ok: false, check, reason: "check_failed" };
  if (check === "xai") {
    // Only a result that came through xAI's moderation can rely on it.
    return moderatedBy === "xai" ? { ok: true, check } : { ok: false, check, reason: "check_failed" };
  }
  const key = options.falKey ?? Deno.env.get("FAL_KEY");
  if (!key) return { ok: false, check, reason: "check_failed" };
  const fetcher = options.fetcher ?? fetch;
  const imageUrls = outputs.map((output) =>
    output.url ?? `data:${output.content_type ?? "image/jpeg"};base64,${output.base64 ?? ""}`
  );
  try {
    const response = await fetcher(FAL_NSFW_URL, {
      method: "POST",
      headers: { Authorization: `Key ${key}`, "Content-Type": "application/json", "X-Fal-Store-IO": "0" },
      body: JSON.stringify({ image_urls: imageUrls }),
      signal: AbortSignal.timeout(FAL_TIMEOUT_MS),
    });
    if (!response.ok) {
      await response.body?.cancel();
      console.error("output check failed", response.status);
      return { ok: false, check, reason: "check_failed" };
    }
    const body = await response.json() as { has_nsfw_concepts?: unknown };
    const flags = body.has_nsfw_concepts;
    // One answer per image, or we can't tell which ones passed.
    if (!Array.isArray(flags) || flags.length !== outputs.length || !flags.every((flag) => typeof flag === "boolean")) {
      console.error("output check returned an unexpected answer");
      return { ok: false, check, reason: "check_failed" };
    }
    return flags.some(Boolean) ? { ok: false, check, reason: "flagged" } : { ok: true, check };
  } catch (error) {
    console.error("output check couldn't run", error instanceof Error ? error.message : error);
    return { ok: false, check, reason: "check_failed" };
  }
}
