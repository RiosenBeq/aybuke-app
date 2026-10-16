// Claude as a text-only helper: the assist function (prompt ideas, prompt
// rewrites, caption ideas, makeup picks) and ai-image's prompt polish. Same
// pinned SDK and client setup as the safety check (safety.ts), Claude Haiku
// 5.5 by default, thinking off at low effort, a small answer in a strict JSON
// schema and a short deadline. Text only: these requests never carry a photo
// or any image. Nothing here logs or returns her text; a failure is a short
// detail ("timeout", "HTTP 529 overloaded_error", "refused"…).
//
// On whenever ANTHROPIC_ASSIST_API_KEY or ANTHROPIC_API_KEY is set. The first
// is optional: a key from a Claude Console workspace of its own, with its own
// rate and spend limits, so writing help can never use up what the safety
// checks need (they keep ANTHROPIC_API_KEY); without it, text help shares the
// safety check's key, and admit_assist()'s ceilings keep it small.
// ANTHROPIC_ASSIST_MODEL picks another model. Like the safety check, the
// model must take thinking turned off at low effort (Claude Opus 5.5 and
// Sonnet 5.5 don't, so every call would fail and the callers fall back).
import Anthropic from "npm:@anthropic-ai/sdk@0.131.0";
import { anthropicClient, anthropicFailure, DEFAULT_ANTHROPIC_MODEL, type SafetyEnv } from "./safety.ts";

/** Where text help's key comes from: its own (optional), else the safety check's. */
export const TEXT_HELPER_SECRETS = ["ANTHROPIC_ASSIST_API_KEY", "ANTHROPIC_API_KEY"] as const;
export type TextHelperSecret = typeof TEXT_HELPER_SECRETS[number];

export interface TextHelperConfig {
  apiKey: string;
  model: string;
  /** The secret the key came from, for the start-up log (never the key). */
  secret?: TextHelperSecret;
}

/** Claude's text help: on with ANTHROPIC_ASSIST_API_KEY or ANTHROPIC_API_KEY (in that order), else off. */
export function textHelperConfig(env: SafetyEnv = Deno.env): TextHelperConfig | undefined {
  for (const secret of TEXT_HELPER_SECRETS) {
    const apiKey = env.get(secret)?.trim();
    if (apiKey) return { apiKey, model: env.get("ANTHROPIC_ASSIST_MODEL")?.trim() || DEFAULT_ANTHROPIC_MODEL, secret };
  }
  return undefined;
}

/** "anthropic:<model> (<secret>)" or "off", for a start-up log line. */
export function describeTextHelper(config: TextHelperConfig | undefined): string {
  return config ? `anthropic:${config.model} (${config.secret ?? "ANTHROPIC_API_KEY"})` : "off";
}

/** One question with a JSON answer: the system prompt, her part as plain text, the answer's schema. */
export interface JsonTask {
  system: string;
  user: string;
  schema: Record<string, unknown>;
  maxTokens: number;
}

export type JsonAnswer =
  | { ok: true; value: unknown }
  | { ok: false; detail: string };

export interface TextHelperOptions {
  /** The most the call may take, its one retry included. */
  deadlineMs: number;
  /** Retries after a 408, 409, 429, 5xx or dropped connection (default 1). */
  maxRetries?: number;
  fetcher?: typeof fetch;
}

export function buildTextRequest(model: string, task: JsonTask): Anthropic.MessageCreateParamsNonStreaming {
  return {
    model,
    max_tokens: task.maxTokens,
    // Short writing and classification: no thinking, low effort (Claude Haiku
    // 5.5 takes disabled thinking at effort high or below, and no temperature).
    thinking: { type: "disabled" },
    output_config: { effort: "low", format: { type: "json_schema", schema: task.schema } },
    system: task.system,
    // Text only, never an image block.
    messages: [{ role: "user", content: task.user }],
  };
}

/** Reads one Messages API answer: exactly one text block of JSON after a normal end, or a short failure. */
export function readJsonAnswer(message: Pick<Anthropic.Message, "stop_reason" | "content">): JsonAnswer {
  if (message.stop_reason === "refusal") return { ok: false, detail: "refused" };
  if (message.stop_reason === "max_tokens") return { ok: false, detail: "cut off" };
  if (message.stop_reason !== "end_turn") return { ok: false, detail: `stopped: ${message.stop_reason}` };
  const texts = message.content.filter((block): block is Anthropic.TextBlock => block.type === "text");
  if (texts.length !== 1) return { ok: false, detail: texts.length === 0 ? "no content" : "unexpected content" };
  try {
    return { ok: true, value: JSON.parse(texts[0].text) };
  } catch {
    return { ok: false, detail: "not JSON" };
  }
}

/** Asks Claude one JSON question. Never throws: an error, a timeout or a refusal comes back as a failure. */
export async function askForJson(
  config: TextHelperConfig,
  task: JsonTask,
  options: TextHelperOptions,
): Promise<JsonAnswer> {
  try {
    const client = anthropicClient({
      apiKey: config.apiKey,
      fetcher: options.fetcher,
      timeoutMs: options.deadlineMs,
      maxRetries: options.maxRetries ?? 1,
    });
    const message = await client.messages.create(buildTextRequest(config.model, task), {
      signal: AbortSignal.timeout(options.deadlineMs),
    });
    return readJsonAnswer(message);
  } catch (error) {
    return { ok: false, detail: anthropicFailure(error) };
  }
}
