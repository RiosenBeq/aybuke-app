// xAI Images API (Grok Imagine): JSON in, base64 out, no queue.
// ai-image runs each request in the background (EdgeRuntime.waitUntil) and the
// app polls the job exactly as with fal. Results are returned inline and are
// cleared as soon as the app confirms the download (sweep_jobs() clears any
// left after an hour). Turn on Zero Data Retention for the xAI team: selfies
// are personal data. Mirrors XAIImagesAPI in AppCore's DirectAI.swift.
import { enhancePrompt } from "./enhance.ts";
import type { JobInput, Operation, Output } from "./fal.ts";
import { requireEnv } from "./http.ts";

/** Best quality for the price (docs/03-product-spec.md, "AI provider"). */
export const DEFAULT_MODEL = "grok-imagine-image-2.0";

/** Unblur & sharpen, the 1.0 Enhance; every mode's instruction is in enhance.ts. */
export const ENHANCE_PROMPT = enhancePrompt("unblur");

export const ERASE_PROMPT =
  "<IMAGE_1> is a mask. Remove everything covered by its white area from <IMAGE_0> and fill that area naturally so it matches the surroundings. Keep everything else in <IMAGE_0> unchanged, with the same framing, and return only the edited <IMAGE_0>.";

/** Background removal always runs on the device. */
export function supports(operation: Operation): boolean {
  return operation !== "remove_background";
}

export function model(operation: Operation): string {
  const image = Deno.env.get("XAI_IMAGE_MODEL") || DEFAULT_MODEL;
  const edit = Deno.env.get("XAI_EDIT_MODEL") || image;
  return operation === "text_to_image" ? image : edit;
}

/**
 * Free runs at low quality and Pro at medium, both at 1k: a cloud operation
 * stays near the ~$0.06 the credit plan is sized for.
 */
export function quality(isPro: boolean): string {
  return isPro ? "medium" : "low";
}

export interface XAIRequest {
  path: "generations" | "edits";
  body: Record<string, unknown>;
}

export function buildRequest(input: JobInput, userTag?: string): XAIRequest {
  const chosen = model(input.operation);
  const body: Record<string, unknown> = {
    model: chosen,
    prompt: input.prompt,
    n: 1,
    resolution: "1k",
    response_format: "b64_json",
  };
  // Only the 2.x models take a quality setting.
  if (chosen.startsWith("grok-imagine-image-2")) body.quality = quality(input.isPro);
  // A one-way tag, so xAI can flag abuse without learning who the user is.
  if (userTag) body.user = userTag;
  const image = (uri: string | undefined) => ({ url: uri, type: "image_url" });

  switch (input.operation) {
    case "text_to_image":
      body.n = input.numOutputs;
      body.aspect_ratio = input.aspectRatio ?? "1:1";
      return { path: "generations", body };
    case "magic_edit":
    case "restyle":
      body.image = image(input.image);
      return { path: "edits", body };
    case "enhance":
      // The mode's own instruction: the request's words never reach the model.
      body.prompt = enhancePrompt(input.enhanceMode);
      body.image = image(input.image);
      return { path: "edits", body };
    case "erase_object":
      body.prompt = ERASE_PROMPT;
      body.images = [image(input.image), image(input.mask)];
      return { path: "edits", body };
    case "remove_background":
      throw new Error("Background removal runs on the device.");
  }
}

/** `moderatedBy: "xai"`: every image passed xAI's own moderation (see moderation.ts). */
export type Outcome =
  | { ok: true; outputs: Output[]; moderatedBy: "xai" }
  | { ok: false; code: string; message: string };

const BLOCKED: Outcome = {
  ok: false,
  code: "content_blocked",
  message: "This result was blocked by our safety filters. Your credit was refunded.",
};

/** Her side of it is a busy service: the app already translates this sentence. */
const BILLING: Outcome = {
  ok: false,
  code: "provider_billing",
  message: "The AI service is busy. Your credit was refunded.",
};

/**
 * Supabase's Free plan stops a function 150 s after its request arrived,
 * background work included, so a job cut off there was never failed or
 * refunded by the function (only later, by the poll's 180 s timeout or
 * sweep_jobs()). Everything a job does ends by WORK_DEADLINE_MS, counted from
 * the request's arrival, leaving 10 s to store the result or fail and refund it.
 */
export const WALL_CLOCK_MS = 150_000;
export const WORK_DEADLINE_MS = 140_000;
/** The most one image request may take: the photo check, if any, comes first and the result check after it. */
export const REQUEST_TIMEOUT_MS = 110_000;
/** Never less than this: a request that can't get it fails at once and is refunded. */
export const MIN_REQUEST_MS = 10_000;

/**
 * How long the image request may take when the job's work has already run
 * `elapsedMs` since the request arrived and `afterMs` must stay free for the
 * result check (safety.CHECK_DEADLINE_MS with the check on, else 0). Zero when
 * less than MIN_REQUEST_MS is left: then the request isn't sent.
 */
export function requestTimeout(elapsedMs: number, afterMs: number): number {
  const left = Math.min(REQUEST_TIMEOUT_MS, WORK_DEADLINE_MS - Math.max(0, elapsedMs) - Math.max(0, afterMs));
  return left >= MIN_REQUEST_MS ? Math.floor(left) : 0;
}

const UNAVAILABLE: Outcome = {
  ok: false,
  code: "provider_unavailable",
  message: "The AI service is busy. Your credit was refunded.",
};

/** Runs one request. Never throws: failures come back as an outcome to refund. */
export async function generate(input: JobInput, userTag?: string, timeoutMs = REQUEST_TIMEOUT_MS): Promise<Outcome> {
  if (timeoutMs <= 0) return UNAVAILABLE;
  const { path, body } = buildRequest(input, userTag);
  let response: Response;
  try {
    response = await fetch(`https://api.x.ai/v1/images/${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requireEnv("XAI_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    console.error("xai request failed", error);
    return UNAVAILABLE;
  }
  const text = await response.text().catch(() => "");
  if (!response.ok) {
    console.error("xai request failed", response.status, text.slice(0, 300));
    return mapError(response.status, text);
  }
  return parseOutputs(text, input.operation === "text_to_image" ? input.numOutputs : 1);
}

/**
 * `data[].b64_json`, with xAI's moderation as the verdict: xAI returns no
 * image data for an image it filtered (and may say `respect_moderation:
 * false`). Fails closed: if any of the `expected` images was filtered or is
 * missing, the whole job is blocked and refunded, never delivered in part.
 */
export function parseOutputs(text: string, expected = 1): Outcome {
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    payload = undefined;
  }
  const data = (payload as { data?: unknown } | undefined)?.data;
  const items = Array.isArray(data) ? data as ({ b64_json?: unknown; respect_moderation?: unknown } | null)[] : [];
  if (items.length === 0) {
    return { ok: false, code: "empty_result", message: "The AI returned no image. Your credit was refunded." };
  }
  const passed = items.filter((item) =>
    item?.respect_moderation !== false && typeof item?.b64_json === "string" && item.b64_json.length > 0
  );
  if (passed.length !== items.length || items.length < expected) return BLOCKED;
  return {
    ok: true,
    moderatedBy: "xai",
    outputs: passed.map((item) => {
      const base64 = item?.b64_json as string;
      return { base64, content_type: base64.startsWith("iVBOR") ? "image/png" : "image/jpeg" };
    }),
  };
}

/**
 * The xAI team is out of credit or over its spending limit: 402, or a 403 or
 * 429 that says so. ai-image refunds the job like any provider failure, then
 * pauses AI (later jobs stop at admit_job) and mails the owner once.
 */
export function isBillingError(status: number, text: string): boolean {
  return status === 402 || ((status === 403 || status === 429) && /credit|balance|billing|spending.?limit/i.test(text));
}

export function mapError(status: number, text: string): Outcome {
  if (status === 402) return BILLING;
  // "imagine:content-moderated" and friends.
  if (/safety|nsfw|content.?policy|moderat|flagged|prohibited/i.test(text)) return BLOCKED;
  if (isBillingError(status, text)) return BILLING;
  if (status === 429) {
    return {
      ok: false,
      code: "provider_busy",
      message: "The AI service is busy. Your credit was refunded. Please try again in a minute.",
    };
  }
  return { ok: false, code: "provider_failed", message: "This creation failed. Your credit was refunded." };
}

/** SHA-256 of the user id, shortened: stable per user, meaningless to xAI. */
export async function userTag(userId: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`glowlit:${userId}`));
  return Array.from(new Uint8Array(digest).slice(0, 12), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
