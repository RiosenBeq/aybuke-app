// "Report this image" (App Store Review Guideline 1.2).
//   POST /report { "reason": "offensive" | "sexual" | "mismatch" | "other", "job_id"?: UUID, "details"?: string }
//   → 201 { "reported": true }
// Reports are reviewed by the team (status in public.reports, ops_reports() in
// the SQL editor) and kept 12 months. file_report() allows reports_per_day per
// user (credit_policy()) and links a job only when it's hers.
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";

const REASONS = new Set(["offensive", "sexual", "mismatch", "other"]);
const MAX_DETAILS = 500;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface ReportRequest {
  reason?: string;
  job_id?: string;
  details?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    const db = serviceClient();
    const user = await requireUser(db, req);
    const body = await req.json().catch(() => ({})) as ReportRequest;
    const reason = body.reason ?? "";
    if (!REASONS.has(reason)) throw new HttpError(400, "bad_request", "Pick a reason for the report.");
    const jobId = typeof body.job_id === "string" && UUID_PATTERN.test(body.job_id) ? body.job_id : null;
    const details = typeof body.details === "string" ? [...body.details.trim()].slice(0, MAX_DETAILS).join("") : "";

    const { data, error } = await db.rpc("file_report", {
      p_user: user.id,
      p_reason: reason,
      p_job: jobId,
      p_details: details || null,
    });
    if (error || !data) throw new HttpError(500, "internal", "Couldn't send the report. Please try again.");
    const result = data as { ok: boolean; code?: string; retry_after?: number };
    if (!result.ok) {
      throw new HttpError(
        429,
        "rate_limited",
        "Thanks — we already have your reports for today.",
        undefined,
        result.retry_after,
      );
    }
    return json({ reported: true }, 201);
  } catch (error) {
    return errorResponse(error);
  }
});
