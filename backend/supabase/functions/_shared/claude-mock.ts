// For tests only: a fetch that answers Claude's Messages API and remembers
// every request, so the real SDK runs and no test reaches the network.
import { DEFAULT_ANTHROPIC_MODEL } from "./safety.ts";

export interface ClaudeRequestBody {
  model: string;
  max_tokens: number;
  thinking: { type: string };
  output_config: { effort: string; format: { type: string; schema: Record<string, unknown> } };
  system: string;
  messages: { role: string; content: unknown }[];
  temperature?: unknown;
}

export interface ClaudeCall {
  url: string;
  headers: Headers;
  body: ClaudeRequestBody;
}

/** A fetch that answers every request with `respond` and remembers what was sent. */
export function mockClaude(respond: (call: ClaudeCall) => Response | Promise<Response>) {
  const calls: ClaudeCall[] = [];
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = { url: String(input), headers: new Headers(init?.headers), body: JSON.parse(String(init?.body)) };
    calls.push(call);
    return await respond(call);
  }) as typeof fetch;
  return { fn, calls };
}

/** A Messages API answer whose one text block is `value` (JSON-encoded unless it's a string). */
export function claudeAnswer(value: unknown, extra: Record<string, unknown> = {}): Response {
  return Response.json({
    id: "msg_test",
    type: "message",
    role: "assistant",
    model: DEFAULT_ANTHROPIC_MODEL,
    content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value), citations: null }],
    stop_reason: "end_turn",
    stop_sequence: null,
    usage: { input_tokens: 700, output_tokens: 90 },
    ...extra,
  });
}

export function claudeError(status: number, type: string, headers: Record<string, string> = {}): Response {
  return Response.json({ type: "error", error: { type, message: "test" } }, { status, headers });
}

/** A fetch that never answers until the request is aborted. */
export const hangingFetch = ((_: unknown, init?: RequestInit) =>
  new Promise<Response>((_resolve, reject) => {
    init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
  })) as typeof fetch;

/**
 * deno test runs without --allow-env (so does CI), and the SDK's constructor
 * reads ANTHROPIC_CUSTOM_HEADERS even with every option given: answer every
 * variable with nothing, so the real client runs against the mocked fetch.
 */
export async function withoutEnv<T>(run: () => Promise<T>): Promise<T> {
  const get = Deno.env.get;
  Deno.env.get = () => undefined;
  try {
    return await run();
  } finally {
    Deno.env.get = get;
  }
}
