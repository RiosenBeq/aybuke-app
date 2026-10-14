// Shared HTTP helpers for Glowlit Edge Functions.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-entitlement-jws, x-app-transaction",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
};

/** Error that maps 1:1 to the `{ "error": { code, message, ... } }` contract the app decodes. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly creditsRemaining?: number,
    /** Seconds until trying again makes sense (sent as Retry-After and `retry_after`). */
    readonly retryAfter?: number,
    /** More fields for the error body, such as `until`. */
    readonly extra: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...headers },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    const body: Record<string, unknown> = { ...error.extra, code: error.code, message: error.message };
    if (error.creditsRemaining !== undefined) body.credits_remaining = error.creditsRemaining;
    const retryAfter = error.retryAfter ?? (error.status === 429 ? 20 : undefined);
    if (retryAfter !== undefined) body.retry_after = retryAfter;
    const headers: Record<string, string> = retryAfter !== undefined ? { "Retry-After": String(retryAfter) } : {};
    return json({ error: body }, error.status, headers);
  }
  console.error("unhandled error", error);
  return json({ error: { code: "internal", message: "Something went wrong. Please try again." } }, 500);
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new HttpError(500, "misconfigured", `Server is missing ${name}.`);
  return value;
}
