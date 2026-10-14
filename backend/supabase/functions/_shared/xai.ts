// xAI Images API (Grok Imagine): JSON in, base64 out, no queue.
// ai-image runs each request in the background (EdgeRuntime.waitUntil) and the
// app polls the job exactly as with fal. Results are returned inline and are
// cleared as soon as the app confirms the download (sweep_jobs() clears any
// left after an hour). Turn on Zero Data Retention for the xAI team: selfies
// are personal data. Mirrors XAIImagesAPI in AppCore's DirectAI.swift.
import type { JobInput, Operation, Output } from "./fal.ts";
import { requireEnv } from "./http.ts";

/** Best quality for the price (docs/03-product-spec.md, "AI provider"). */
export const DEFAULT_MODEL = "grok-imagine-image-2.0";

export const ENHANCE_PROMPT =
  "Enhance this photo: make it sharper and more detailed, reduce blur and noise, restore faces naturally and gently improve the lighting. Keep real skin texture, freckles, moles, pores and blemishes; don't retouch or smooth the skin, and don't reshape the face or body. Keep the composition, colors, every person and their identity exactly the same.";

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
      body.prompt = ENHANCE_PROMPT;
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

export type Outcome =
  | { ok: true; outputs: Output[] }
  | { ok: false; code: string; message: string };

const BLOCKED: Outcome = {
  ok: false,
  code: "content_blocked",
  message: "This result was blocked by our safety filters. Your credit was refunded.",
};

/** Runs one request. Never throws: failures come back as an outcome to refund. */
export async function generate(input: JobInput, userTag?: string, timeoutMs = 150_000): Promise<Outcome> {
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
    return { ok: false, code: "provider_unavailable", message: "The AI service is busy. Your credit was refunded." };
  }
  const text = await response.text().catch(() => "");
  if (!response.ok) {
    console.error("xai request failed", response.status, text.slice(0, 300));
    return mapError(response.status, text);
  }
  return parseOutputs(text);
}

/** `data[].b64_json`; outputs xAI's moderation filtered are dropped. */
export function parseOutputs(text: string): Outcome {
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    payload = undefined;
  }
  const data = (payload as { data?: unknown } | undefined)?.data;
  const items = Array.isArray(data) ? data as { b64_json?: unknown; respect_moderation?: unknown }[] : [];
  const kept = items.filter((item) => item?.respect_moderation !== false && typeof item?.b64_json === "string");
  if (kept.length === 0) {
    if (items.some((item) => item?.respect_moderation === false)) return BLOCKED;
    return { ok: false, code: "empty_result", message: "The AI returned no image. Your credit was refunded." };
  }
  return {
    ok: true,
    outputs: kept.map((item) => {
      const base64 = item.b64_json as string;
      return { base64, content_type: base64.startsWith("iVBOR") ? "image/png" : "image/jpeg" };
    }),
  };
}

export function mapError(status: number, text: string): Outcome {
  if (/safety|nsfw|content.?policy|moderation|flagged|prohibited/i.test(text)) return BLOCKED;
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
