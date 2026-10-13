// fal.ai queue client and per-operation request builders.
// Endpoint ids and JSON shapes: docs/research/tech-and-compliance.md §2.4
// (from fal's official client types). Never expose a generic proxy to the app:
// the client only names an *operation*, the server picks the model.
import { HttpError, requireEnv } from "./http.ts";

export type Operation =
  | "text_to_image"
  | "magic_edit"
  | "enhance"
  | "remove_background"
  | "erase_object"
  | "restyle";

export const OPERATIONS: ReadonlySet<string> = new Set<Operation>([
  "text_to_image",
  "magic_edit",
  "enhance",
  "remove_background",
  "erase_object",
  "restyle",
]);

/** Default model per operation (late-2026 picks; swap here, no app release needed). */
export const ENDPOINTS: Record<Operation, string> = {
  text_to_image: "fal-ai/nano-banana-2",
  magic_edit: "fal-ai/nano-banana-2/edit",
  restyle: "fal-ai/nano-banana-2/edit",
  enhance: "fal-ai/seedvr/upscale/image",
  remove_background: "fal-ai/birefnet/v2",
  erase_object: "fal-ai/object-removal/mask",
};

export interface JobInput {
  operation: Operation;
  prompt?: string;
  aspectRatio?: string;
  numOutputs: number;
  image?: string;
  mask?: string;
  isPro: boolean;
}

/** Builds the model input JSON. Images are passed as data URIs (never stored by us). */
export function buildFalInput(input: JobInput): Record<string, unknown> {
  const resolution = input.isPro ? "2K" : "1K";
  switch (input.operation) {
    case "text_to_image":
      return {
        prompt: input.prompt,
        aspect_ratio: input.aspectRatio ?? "1:1",
        resolution,
        num_images: input.numOutputs,
        output_format: "jpeg",
        safety_tolerance: "2",
        limit_generations: true,
      };
    case "magic_edit":
    case "restyle":
      return {
        prompt: input.prompt,
        image_urls: [input.image],
        aspect_ratio: "auto",
        resolution,
        num_images: 1,
        output_format: "jpeg",
        safety_tolerance: "2",
      };
    case "enhance":
      return { image_url: input.image, upscale_mode: "factor", upscale_factor: 2 };
    case "remove_background":
      return {
        image_url: input.image,
        model: "General Use (Heavy)",
        operating_resolution: "2048x2048",
        output_format: "png",
        refine_foreground: true,
      };
    case "erase_object":
      return { image_url: input.image, mask_url: input.mask, model: "best_quality", mask_expansion: 15 };
  }
}

export interface QueuedRequest {
  request_id: string;
  status_url: string;
  response_url: string;
  cancel_url: string;
}

/** A result: a provider CDN link (fal) or the image itself, base64 (xAI). */
export interface Output {
  url?: string;
  base64?: string;
  width?: number;
  height?: number;
  content_type?: string;
}

function headers(): HeadersInit {
  return {
    Authorization: `Key ${requireEnv("FAL_KEY")}`,
    "Content-Type": "application/json",
    // Outputs expire on fal's CDN after an hour; the app downloads them immediately.
    "X-Fal-Object-Lifecycle-Preference": JSON.stringify({ expiration_duration_seconds: 3600 }),
    // Don't keep request inputs/outputs in fal's request history.
    "X-Fal-Store-IO": "0",
  };
}

export async function submit(endpoint: string, body: Record<string, unknown>): Promise<QueuedRequest> {
  const response = await fetch(`https://queue.fal.run/${endpoint}`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    console.error("fal submit failed", response.status, await safeText(response));
    throw new HttpError(502, "provider_unavailable", "The AI service is busy. Please try again.");
  }
  return await response.json() as QueuedRequest;
}

export type QueueStatus = "IN_QUEUE" | "IN_PROGRESS" | "COMPLETED";

export async function status(statusUrl: string): Promise<QueueStatus | "UNKNOWN"> {
  const response = await fetch(statusUrl, { headers: headers() });
  if (!response.ok) return "UNKNOWN";
  const body = await response.json() as { status?: QueueStatus };
  return body.status ?? "UNKNOWN";
}

export type ResultOutcome =
  | { ok: true; outputs: Output[] }
  | { ok: false; code: string; message: string };

/** Fetches a completed request's output, mapping provider errors to app error codes. */
export async function result(responseUrl: string): Promise<ResultOutcome> {
  const response = await fetch(responseUrl, { headers: headers() });
  const text = await safeText(response);
  if (!response.ok) {
    const blocked = /safety|nsfw|content.?policy|moderation|flagged/i.test(text);
    return blocked
      ? {
        ok: false,
        code: "content_blocked",
        message: "This edit was blocked by our safety filters. Your credit was refunded.",
      }
      : { ok: false, code: "provider_failed", message: "This creation failed. Your credit was refunded." };
  }
  const outputs = normalizeOutputs(JSON.parse(text));
  return outputs.length > 0
    ? { ok: true, outputs }
    : { ok: false, code: "empty_result", message: "The AI returned no image. Your credit was refunded." };
}

export async function cancel(cancelUrl: string): Promise<void> {
  await fetch(cancelUrl, { method: "PUT", headers: headers() }).catch(() => undefined);
}

/** Models return either `images: [...]` or `image: {...}`. */
export function normalizeOutputs(payload: unknown): Output[] {
  if (!payload || typeof payload !== "object") return [];
  const record = payload as { images?: unknown; image?: unknown };
  const list = Array.isArray(record.images) ? record.images : record.image ? [record.image] : [];
  return list
    .filter((item): item is Output => !!item && typeof (item as Output).url === "string")
    .map(({ url, width, height, content_type }) => ({ url, width, height, content_type }));
}

/**
 * Second safety net on outputs (on by default; `OUTPUT_MODERATION=off` disables it).
 * Part of the documented safeguards for EU AI Act Art. 5(1)(ba) (from 2 Dec 2026).
 */
export async function outputsLookUnsafe(outputs: Output[]): Promise<boolean> {
  if (Deno.env.get("OUTPUT_MODERATION") === "off" || outputs.length === 0) return false;
  // With xAI alone (no fal key) its own moderation is the output check.
  if (!Deno.env.get("FAL_KEY")) return false;
  const imageUrls = outputs.map((o) => o.url ?? `data:${o.content_type ?? "image/jpeg"};base64,${o.base64 ?? ""}`);
  const response = await fetch("https://fal.run/fal-ai/x-ailab/nsfw", {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({ image_urls: imageUrls }),
  });
  if (!response.ok) return false;
  const body = await response.json() as { has_nsfw_concepts?: boolean[] };
  return (body.has_nsfw_concepts ?? []).some(Boolean);
}

async function safeText(response: Response): Promise<string> {
  try {
    return await response.text();
  } catch {
    return "";
  }
}
