// What admit_job() (20261022 migration) answers, and the error the app gets
// for each refusal. The app shows its own translated sentence for each code
// (AppModel.serverMessages); these English messages are the fallback.
import { HttpError } from "./http.ts";

export interface AdmitResult {
  ok: boolean;
  job_id?: string;
  credits_remaining?: number;
  code?: string;
  status?: number;
  retry_after?: number;
  until?: string;
  category?: string;
}

export const ADMISSION_MESSAGES: Record<string, string> = {
  install_blocked:
    "Cloud AI is turned off here for now. Your free tools still work. If you think this is a mistake, contact us.",
  cooldown: "Cloud AI is taking a break for now. Your free tools still work in the meantime.",
  ai_paused: "AI is taking a short break. Please try again later. Your free tools still work.",
  rate_limited: "Too many requests. Please wait a moment.",
  usage_limit: "You've made a lot in a short time. Take a little break and try again later.",
  retry_unavailable: "This result can't be retried for free anymore.",
  retry_limit: "You've used today's free retries.",
  app_transaction_required:
    "We couldn't confirm this copy of Glowlit with the App Store, so free credits aren't available right now.",
  app_transaction_invalid:
    "We couldn't confirm this copy of Glowlit with the App Store, so free credits aren't available right now.",
  insufficient_credits: "You're out of credits.",
};

/** The refusal as an HTTP error, with Retry-After, `until` and the balance when known. */
export function admissionError(result: AdmitResult, blockedReason?: string): HttpError {
  const code = result.code ?? "internal";
  const message = code === "content_blocked"
    ? blockedReason ?? "This request isn't allowed by our content policy."
    : ADMISSION_MESSAGES[code] ?? "Something went wrong. Please try again.";
  const extra: Record<string, unknown> = {};
  if (result.until) extra.until = result.until;
  return new HttpError(result.status ?? 500, code, message, result.credits_remaining, result.retry_after, extra);
}
