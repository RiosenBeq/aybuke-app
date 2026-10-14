// Optional independent safety check with an xAI vision model: every result,
// and the photo before an edit runs (it costs a fraction of a cent, and a
// photo that fails never reaches the image model). Off unless
// XAI_SAFETY_MODEL names a vision model (for example a grok-4 fast model);
// when it's on it fails closed: an error, a timeout, a refusal or an answer
// that isn't the expected JSON blocks the job, which is refunded. It runs on
// top of the output check in moderation.ts, never instead of it. xAI is
// already the image processor, so no new processor sees the images (Zero
// Data Retention applies to the same team).
//
// Not enabled by default: it can't be tested against the live API yet.
// Unit tests (safety_test.ts) mock every answer.

export interface SafetyEnv {
  get(name: string): string | undefined;
}

export type SafetySubject = "photo" | "result";

export type SafetyVerdict =
  | { ok: true }
  | { ok: false; reason: "flagged"; categories: string[] }
  | { ok: false; reason: "check_failed"; detail: string };

export const XAI_CHAT_URL = "https://api.x.ai/v1/chat/completions";
const TIMEOUT_MS = 20_000;

export const CATEGORIES = ["nudity", "sexual", "minor_sexualized", "graphic_violence", "self_harm", "hate"] as const;

/** The vision model, or undefined when the check is off. */
export function safetyModel(env: SafetyEnv = Deno.env): string | undefined {
  const model = env.get("XAI_SAFETY_MODEL")?.trim();
  return model || undefined;
}

export const SYSTEM_PROMPT =
  "You review images for a photo app used by teenagers (13 and older). Flag an image only for these " +
  "categories: nudity (exposed genitals, buttocks or female nipples, also through see-through clothing); " +
  "sexual (sexual activity, sexualized posing or focus on intimate body parts, lingerie or underwear as the " +
  "focus); minor_sexualized (anything sexualizing a person who may be under 18); graphic_violence (gore or " +
  "serious injury); self_harm; hate (hate symbols or slurs). Everyday clothing, swimwear in an ordinary beach " +
  "or pool scene, makeup, costumes, cartoons and art styles are fine. Answer only with the JSON object.";

const RESPONSE_FORMAT = {
  type: "json_schema",
  json_schema: {
    name: "safety_verdict",
    strict: true,
    schema: {
      type: "object",
      properties: {
        flagged: { type: "boolean" },
        categories: { type: "array", items: { type: "string", enum: [...CATEGORIES] } },
      },
      required: ["flagged", "categories"],
      additionalProperties: false,
    },
  },
};

export function buildRequest(model: string, image: string, subject: SafetySubject): Record<string, unknown> {
  return {
    model,
    temperature: 0,
    max_tokens: 200,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          { type: "image_url", image_url: { url: image, detail: "low" } },
          {
            type: "text",
            text: subject === "photo"
              ? "This is the photo someone wants to edit. Classify it."
              : "This is an AI-made image about to be shown. Classify it.",
          },
        ],
      },
    ],
    response_format: RESPONSE_FORMAT,
  };
}

/** Reads one chat completion. Anything but a well-formed verdict is a failed check. */
export function parseVerdict(body: unknown): SafetyVerdict {
  const message = (body as { choices?: { message?: { content?: unknown; refusal?: unknown } }[] } | null)
    ?.choices?.[0]?.message;
  if (!message) return { ok: false, reason: "check_failed", detail: "no message" };
  if (message.refusal) return { ok: false, reason: "check_failed", detail: "refused" };
  if (typeof message.content !== "string") return { ok: false, reason: "check_failed", detail: "no content" };
  let verdict: unknown;
  try {
    verdict = JSON.parse(message.content);
  } catch {
    return { ok: false, reason: "check_failed", detail: "not JSON" };
  }
  const { flagged, categories } = (verdict ?? {}) as { flagged?: unknown; categories?: unknown };
  if (typeof flagged !== "boolean" || !Array.isArray(categories) || !categories.every((c) => typeof c === "string")) {
    return { ok: false, reason: "check_failed", detail: "unexpected shape" };
  }
  const known = (categories as string[]).filter((c) => (CATEGORIES as readonly string[]).includes(c));
  // A category alone flags the image too: never let a contradiction through.
  if (flagged || known.length > 0) return { ok: false, reason: "flagged", categories: known };
  return { ok: true };
}

export interface SafetyOptions {
  model: string;
  apiKey: string;
  fetcher?: typeof fetch;
  timeoutMs?: number;
}

async function classifyOne(image: string, subject: SafetySubject, options: SafetyOptions): Promise<SafetyVerdict> {
  const fetcher = options.fetcher ?? fetch;
  try {
    const response = await fetcher(XAI_CHAT_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(buildRequest(options.model, image, subject)),
      signal: AbortSignal.timeout(options.timeoutMs ?? TIMEOUT_MS),
    });
    if (!response.ok) {
      await response.body?.cancel();
      return { ok: false, reason: "check_failed", detail: `HTTP ${response.status}` };
    }
    return parseVerdict(await response.json());
  } catch (error) {
    return { ok: false, reason: "check_failed", detail: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * Classifies every image (data URIs or URLs). Flagged if any is flagged;
 * otherwise failed if any check failed. Never throws.
 */
export async function classifyImages(
  images: string[],
  subject: SafetySubject,
  options: SafetyOptions,
): Promise<SafetyVerdict> {
  if (images.length === 0) return { ok: false, reason: "check_failed", detail: "no images" };
  const verdicts = await Promise.all(images.map((image) => classifyOne(image, subject, options)));
  const flagged = verdicts.filter((v): v is Extract<SafetyVerdict, { reason: "flagged" }> => !v.ok && v.reason === "flagged");
  if (flagged.length > 0) return { ok: false, reason: "flagged", categories: [...new Set(flagged.flatMap((v) => v.categories))] };
  const failed = verdicts.find((v): v is Extract<SafetyVerdict, { reason: "check_failed" }> => !v.ok);
  return failed ?? { ok: true };
}
