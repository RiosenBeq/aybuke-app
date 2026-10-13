// "Report this image" (App Store Review Guideline 1.2).
//   POST /report { "reason": "offensive" | "sexual" | "mismatch" | "other", "job_id"?: UUID, "details"?: string }
//   → 201 { "reported": true }
// Reports are reviewed by the team (status in public.reports) and kept 12 months.
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";

const REASONS = new Set(["offensive", "sexual", "mismatch", "other"]);
const MAX_DETAILS = 500;
const DAILY_LIMIT = 20;
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

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count } = await db.from("reports")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", since);
    if ((count ?? 0) >= DAILY_LIMIT) {
      throw new HttpError(429, "rate_limited", "Thanks — we already have your reports for today.");
    }

    // Only link jobs that belong to this user.
    let jobId: string | null = null;
    if (body.job_id && UUID_PATTERN.test(body.job_id)) {
      const { data } = await db.from("jobs").select("id").eq("id", body.job_id).eq("user_id", user.id).maybeSingle();
      jobId = data?.id ?? null;
    }
    const details = typeof body.details === "string" ? body.details.trim().slice(0, MAX_DETAILS) : "";

    const { error } = await db.from("reports").insert({
      user_id: user.id,
      job_id: jobId,
      reason,
      details: details || null,
    });
    if (error) throw new HttpError(500, "internal", "Couldn't send the report. Please try again.");
    return json({ reported: true }, 201);
  } catch (error) {
    return errorResponse(error);
  }
});
