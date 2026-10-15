// The safety check's circuit breaker (20261029000001_safety_breaker.sql).
//
// The independent check (safety.ts) fails closed, so while Anthropic is down
// every job is refunded, and a creation is refunded only after xAI made and
// billed its image. ai-image reports each check that couldn't run here; three
// within ten minutes turn the 'all' pause on for five minutes (longer when it
// trips again soon after), so admit_job() refuses new jobs with ai_paused
// before anything is charged or sent to xAI. A verdict, a refusal or an image
// the model can't take is no outage and isn't reported.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { isServiceFailure, type SafetyVerdict } from "./safety.ts";

type Db = Pick<SupabaseClient, "rpc">;

/**
 * Reports a check that couldn't run. Returns when the pause it started ends,
 * or undefined (no pause started, nothing to report, or the report failed:
 * logged, never thrown, and the job is refunded either way).
 */
export async function noteSafetyCheckError(db: Db, verdict: SafetyVerdict): Promise<string | undefined> {
  if (!isServiceFailure(verdict) || verdict.ok || verdict.reason !== "check_failed") return undefined;
  try {
    const { data, error } = await db.rpc("note_safety_check_error", { p_detail: verdict.detail })
      .abortSignal(AbortSignal.timeout(5_000));
    if (error) {
      console.error("note_safety_check_error failed", error.message);
      return undefined;
    }
    if (typeof data !== "string") return undefined;
    console.warn(`AI paused until ${data}: the safety check failed repeatedly (last: ${verdict.detail})`);
    return data;
  } catch (error) {
    console.error("note_safety_check_error failed", error instanceof Error ? error.message : error);
    return undefined;
  }
}
