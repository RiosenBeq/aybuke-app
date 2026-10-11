// Glowlit AI jobs API.
//
//   POST   /ai-image            enqueue a job        → 202 { job_id, status: "queued", credits_remaining }
//   GET    /ai-image?job_id=ID  poll a job            → { job_id, status, outputs?, error?, credits_remaining? }
//   DELETE /ai-image?job_id=ID  cancel + refund a job → { job_id, status: "cancelled", credits_remaining }
//   GET    /ai-image            current balance       → { credits_remaining, is_pro }
//
// Contract: ios/Packages/AppCore/Sources/AppCore/BackendAPI.swift
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { resolveEntitlement } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import * as fal from "../_shared/fal.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import { evaluatePrompt } from "../_shared/policy.ts";
import { PRO_STYLES, templateRecipe } from "../_shared/templates.ts";

const MAX_BODY_BYTES = 8 * 1024 * 1024;
const MAX_PROMPT_LENGTH = 1000;
const MAX_OUTPUTS = 4;
const FREE_RETRY_WINDOW_MINUTES = 15;
const JOB_TIMEOUT_MS = 10 * 60 * 1000;
const RATE_LIMIT_PER_MINUTE = { free: 6, pro: 20 };
const ASPECT_RATIOS = new Set(["1:1", "3:4", "9:16", "4:3", "16:9"]);

interface GenerationRequest {
  operation?: string;
  prompt?: string;
  style_id?: string;
  template_id?: string;
  aspect_ratio?: string;
  num_outputs?: number;
  image?: string;
  mask?: string;
  retry_of?: string;
}

interface JobRow {
  id: string;
  user_id: string;
  operation: string;
  status: "queued" | "processing" | "completed" | "failed" | "cancelled";
  status_url: string | null;
  response_url: string | null;
  cancel_url: string | null;
  outputs: fal.Output[] | null;
  error_code: string | null;
  error_message: string | null;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const db = serviceClient();
    const user = await requireUser(db, req);
    const url = new URL(req.url);
    const jobId = url.searchParams.get("job_id");

    switch (req.method) {
      case "POST": {
        const isPro = await resolveEntitlement(db, user.id, req.headers.get("x-entitlement-jws"));
        return await createJob(db, user.id, isPro, req);
      }
      case "GET": {
        if (jobId) return await pollJob(db, user.id, jobId);
        const isPro = await resolveEntitlement(db, user.id, req.headers.get("x-entitlement-jws"));
        return json({ credits_remaining: await balance(db, user.id, isPro), is_pro: isPro });
      }
      case "DELETE":
        if (!jobId) throw new HttpError(400, "bad_request", "Missing job_id.");
        return await cancelJob(db, user.id, jobId);
      default:
        throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    }
  } catch (error) {
    return errorResponse(error);
  }
});

// MARK: - Create

async function createJob(db: SupabaseClient, userId: string, isPro: boolean, req: Request): Promise<Response> {
  const length = Number(req.headers.get("content-length") ?? "0");
  if (length > MAX_BODY_BYTES) throw new HttpError(413, "too_large", "That photo is too large. Try a smaller one.");
  const body = await req.json().catch(() => {
    throw new HttpError(400, "bad_request", "Invalid JSON body.");
  }) as GenerationRequest;

  const operation = body.operation ?? "";
  if (!fal.OPERATIONS.has(operation)) throw new HttpError(400, "bad_request", "Unknown operation.");
  const op = operation as fal.Operation;
  const numOutputs = Math.trunc(body.num_outputs ?? 1);
  if (numOutputs < 1 || numOutputs > MAX_OUTPUTS) {
    throw new HttpError(400, "bad_request", "You can create 1–4 images at a time.");
  }
  if (numOutputs > 1 && !isPro) {
    throw new HttpError(402, "pro_required", "Creating several images at once is a Pro feature.");
  }
  if (op !== "text_to_image" && !isImageDataURI(body.image)) {
    throw new HttpError(400, "bad_request", "Pick a photo first.");
  }
  if (op === "erase_object" && !isImageDataURI(body.mask)) {
    throw new HttpError(400, "bad_request", "Brush over what you want to erase.");
  }
  if (body.style_id && PRO_STYLES.has(body.style_id) && !isPro) {
    throw new HttpError(402, "pro_required", "This style is part of Pro.");
  }

  let prompt = (body.prompt ?? "").trim().slice(0, MAX_PROMPT_LENGTH);
  let endpoint = fal.ENDPOINTS[op];
  if (op === "restyle") {
    const recipe = templateRecipe(body.template_id ?? "");
    if (!recipe) {
      throw new HttpError(400, "bad_request", "This style is no longer available. Update the app to see the latest.");
    }
    if (recipe.isPro && !isPro) throw new HttpError(402, "pro_required", "This template is part of Pro.");
    prompt = recipe.prompt;
    endpoint = recipe.endpoint ?? endpoint;
  }
  if ((op === "text_to_image" || op === "magic_edit") && !prompt) {
    throw new HttpError(400, "bad_request", "Describe what you want to see.");
  }
  const verdict = evaluatePrompt(prompt);
  if (!verdict.allowed) throw new HttpError(422, "content_blocked", verdict.reason);

  await enforceRateLimit(db, userId, isPro);

  // Likeness Lock: one free retry of a recent result.
  let cost = numOutputs;
  if (body.retry_of) {
    const { data: original } = await db
      .from("jobs")
      .update({ retried: true, updated_at: new Date().toISOString() })
      .eq("id", body.retry_of)
      .eq("user_id", userId)
      .eq("operation", op)
      .eq("status", "completed")
      .eq("retried", false)
      .gt("created_at", new Date(Date.now() - FREE_RETRY_WINDOW_MINUTES * 60_000).toISOString())
      .select("id")
      .maybeSingle();
    if (!original) throw new HttpError(409, "retry_unavailable", "This result can't be retried for free anymore.");
    cost = 0;
  }

  const { data: job, error: insertError } = await db
    .from("jobs")
    .insert({
      user_id: userId,
      operation: op,
      template_id: body.template_id ?? null,
      endpoint,
      cost,
      retry_of: body.retry_of ?? null,
    })
    .select("id")
    .single();
  if (insertError || !job) throw new HttpError(500, "internal", "Couldn't start the job.");

  const { data: remaining, error: reserveError } = await db.rpc("reserve_credits", {
    p_user: userId,
    p_is_pro: isPro,
    p_cost: cost,
    p_job: job.id,
  });
  if (reserveError) {
    await db.from("jobs").update({ status: "failed", error_code: "insufficient_credits" }).eq("id", job.id);
    if (reserveError.message.includes("INSUFFICIENT_CREDITS")) {
      throw new HttpError(402, "insufficient_credits", "You're out of credits.", await balance(db, userId, isPro));
    }
    throw new HttpError(500, "internal", "Couldn't reserve credits.");
  }

  try {
    const queued = await fal.submit(
      endpoint,
      fal.buildFalInput({
        operation: op,
        prompt,
        aspectRatio: body.aspect_ratio && ASPECT_RATIOS.has(body.aspect_ratio) ? body.aspect_ratio : undefined,
        numOutputs,
        image: body.image,
        mask: body.mask,
        isPro,
      }),
    );
    await db.from("jobs").update({
      fal_request_id: queued.request_id,
      status_url: queued.status_url,
      response_url: queued.response_url,
      cancel_url: queued.cancel_url,
      updated_at: new Date().toISOString(),
    }).eq("id", job.id);
  } catch (error) {
    await failJob(db, job.id, "provider_unavailable", "The AI service is busy. Your credit was refunded.");
    throw error;
  }

  return json({ job_id: job.id, status: "queued", credits_remaining: remaining }, 202);
}

// MARK: - Poll

async function pollJob(db: SupabaseClient, userId: string, jobId: string): Promise<Response> {
  const job = await loadJob(db, userId, jobId);
  if (job.status === "queued" || job.status === "processing") {
    await advance(db, job);
  }
  const fresh = await loadJob(db, userId, jobId);
  return json(present(fresh));
}

/** Moves a pending job forward by asking the provider (no webhook needed). */
async function advance(db: SupabaseClient, job: JobRow): Promise<void> {
  if (Date.now() - new Date(job.created_at).getTime() > JOB_TIMEOUT_MS) {
    if (job.cancel_url) await fal.cancel(job.cancel_url);
    await failJob(db, job.id, "timeout", "This took too long. Your credit was refunded.");
    return;
  }
  if (!job.status_url || !job.response_url) return;

  const state = await fal.status(job.status_url);
  if (state === "IN_PROGRESS" && job.status === "queued") {
    await db.from("jobs").update({ status: "processing", updated_at: new Date().toISOString() })
      .eq("id", job.id).eq("status", "queued");
    return;
  }
  if (state !== "COMPLETED") return;

  const outcome = await fal.result(job.response_url);
  if (!outcome.ok) {
    await failJob(db, job.id, outcome.code, outcome.message);
    return;
  }
  if (await fal.outputsLookUnsafe(outcome.outputs)) {
    await failJob(
      db,
      job.id,
      "content_blocked",
      "This result was blocked by our safety filters. Your credit was refunded.",
    );
    return;
  }
  await db.from("jobs")
    .update({ status: "completed", outputs: outcome.outputs, updated_at: new Date().toISOString() })
    .eq("id", job.id)
    .in("status", ["queued", "processing"]);
}

// MARK: - Cancel

async function cancelJob(db: SupabaseClient, userId: string, jobId: string): Promise<Response> {
  const job = await loadJob(db, userId, jobId);
  if (job.status === "queued" || job.status === "processing") {
    if (job.cancel_url) await fal.cancel(job.cancel_url);
    const { data } = await db.from("jobs")
      .update({ status: "cancelled", updated_at: new Date().toISOString() })
      .eq("id", job.id)
      .in("status", ["queued", "processing"])
      .select("id");
    if (data && data.length > 0) {
      const { data: remaining } = await db.rpc("release_credits", { p_job: job.id });
      return json({ job_id: job.id, status: "cancelled", credits_remaining: remaining ?? undefined });
    }
  }
  return json(present(await loadJob(db, userId, jobId)));
}

// MARK: - Helpers

async function loadJob(db: SupabaseClient, userId: string, jobId: string): Promise<JobRow> {
  const { data } = await db.from("jobs").select("*").eq("id", jobId).eq("user_id", userId).maybeSingle();
  if (!data) throw new HttpError(404, "not_found", "That job doesn't exist.");
  return data as JobRow;
}

/** Marks a pending job failed and refunds it (both idempotent). */
async function failJob(db: SupabaseClient, jobId: string, code: string, message: string): Promise<void> {
  const { data } = await db.from("jobs")
    .update({ status: "failed", error_code: code, error_message: message, updated_at: new Date().toISOString() })
    .eq("id", jobId)
    .in("status", ["queued", "processing"])
    .select("id");
  if (data && data.length > 0) {
    await db.rpc("release_credits", { p_job: jobId });
  }
}

function present(job: JobRow): Record<string, unknown> {
  const body: Record<string, unknown> = { job_id: job.id, status: job.status };
  if (job.status === "completed") body.outputs = job.outputs ?? [];
  if (job.status === "failed") {
    body.error = {
      code: job.error_code ?? "job_failed",
      message: job.error_message ?? "This creation failed. Your credit was refunded.",
    };
  }
  return body;
}

async function balance(db: SupabaseClient, userId: string, isPro: boolean): Promise<number> {
  const { data, error } = await db.rpc("refresh_wallet", { p_user: userId, p_is_pro: isPro });
  if (error || !data) return 0;
  const wallet = data as { daily: number; subscription: number; purchased: number };
  return wallet.daily + wallet.subscription + wallet.purchased;
}

async function enforceRateLimit(db: SupabaseClient, userId: string, isPro: boolean): Promise<void> {
  const since = new Date(Date.now() - 60_000).toISOString();
  const { count } = await db.from("jobs")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", since);
  const limit = isPro ? RATE_LIMIT_PER_MINUTE.pro : RATE_LIMIT_PER_MINUTE.free;
  if ((count ?? 0) >= limit) throw new HttpError(429, "rate_limited", "Too many requests. Please wait a moment.");
}

function isImageDataURI(value: string | undefined): value is string {
  return typeof value === "string" && /^data:image\/(jpeg|png|webp|heic);base64,/.test(value);
}
