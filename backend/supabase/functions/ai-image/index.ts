// Glowlit AI jobs API.
//
//   POST   /ai-image            enqueue a job        → 202 { job_id, status: "queued", credits_remaining }
//   GET    /ai-image?job_id=ID  poll a job            → { job_id, status, outputs?, error?, credits_remaining? }
//          [&wait=S]            (credits_remaining once the job is finished). Held while the job runs,
//                               until it finishes or S seconds pass (0–20, default 20; long-poll.ts)
//   DELETE /ai-image?job_id=ID  cancel + refund a job → { job_id, status: "cancelled", credits_remaining }
//          [&intent=cancel]     (on a completed job the app received: a plain DELETE is the "got it" that
//                               clears the results; intent=cancel means the app gave up waiting)
//   GET    /ai-image            balance and policy    → { credits_remaining, is_pro, free_credits, ai_status,
//                                                         cooldown_until?, policy: { free_daily, pro_monthly,
//                                                         rollover_cap, trial_credits, free_retries_daily } }
//
// Headers: Authorization (the user's session), X-Entitlement-JWS (Pro's signed
// transaction, optional) and X-App-Transaction (StoreKit's signed
// AppTransaction: free credits belong to a verified App Store install, see
// _shared/apple.ts and the 20261021 migration).
//
// Contract: ios/Packages/AppCore/Sources/AppCore/BackendAPI.swift
//
// Every job goes through admit_job() (20261022): blocks, cool-downs, the
// prompt policy's strikes, circuit breakers, rate limits, free retries and
// the charge, in one transaction. Providers: xAI (default when XAI_API_KEY is
// set) or fal (AI_PROVIDER=fal). fal jobs are queued at fal and advanced while
// the app polls; xAI answers in one request, which runs in the background
// after the 202. When xAI refuses a job for billing, AI pauses for everyone
// and the owner gets a mail; each billed job checks the estimated balance
// (_shared/provider-alerts.ts). Every result passes the output check
// (moderation.ts) and, when it's on, the independent check (safety.ts: Claude
// with ANTHROPIC_API_KEY, or an xAI model with XAI_SAFETY_MODEL; it also checks
// the photo before an edit), or is blocked and refunded, and a flagged result
// counts as a strike. The poll that returns the results records the delivery;
// a DELETE on a delivered job confirms the app has the images and clears them
// right away. Results the app never received are refunded (cancel_job(),
// settle_unconfirmed(), sweep_jobs()).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";
import { admissionError, type AdmitResult } from "../_shared/admission.ts";
import { type EntitlementStatus, type InstallProof, resolveEntitlement, verifyInstall } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import * as fal from "../_shared/fal.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import {
  checkImage,
  clientIp,
  MAX_IMAGE_BYTES,
  MAX_PROMPT_CHARS,
  promptLength,
  sanitizePrompt,
} from "../_shared/input.ts";
import { checkOutputs, outputCheck } from "../_shared/moderation.ts";
import { runInBackground } from "../_shared/owner-mail.ts";
import { EDIT_GUARD, evaluatePrompt, type Verdict } from "../_shared/policy.ts";
import { checkProviderBudget, pauseForProviderBilling } from "../_shared/provider-alerts.ts";
import {
  API_KEY_SECRET,
  classifyImages,
  safetyConfig,
  type SafetySubject,
  type SafetyVerdict,
} from "../_shared/safety.ts";
import { PRO_STYLES, templateRecipe } from "../_shared/templates.ts";
import * as xai from "../_shared/xai.ts";
import { holdWhilePending, isPending, waitSeconds } from "./long-poll.ts";

// An erase sends a photo and a mask, each at MAX_IMAGE_BYTES (6 MiB), which is
// 8 MiB as base64 (4/3). Plus about 256 KiB of JSON: the app's prompt is at most
// 1,200 code points (under 7 KB even escaped) and the data-URI labels are 23
// bytes each. A body over the cap is refused, so the cap bounds the memory read.
const MAX_BODY_BYTES = 2 * ((MAX_IMAGE_BYTES / 3) * 4) + 256 * 1024;
const MAX_OUTPUTS = 4;
const JOB_TIMEOUT_MS = 10 * 60 * 1000;
/** xAI requests are synchronous; a job still pending after this has stalled. */
const XAI_JOB_TIMEOUT_MS = 3 * 60 * 1000;
const ASPECT_RATIOS = new Set(["1:1", "3:4", "9:16", "4:3", "16:9"]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface GenerationRequest {
  operation?: unknown;
  prompt?: unknown;
  style_id?: unknown;
  template_id?: unknown;
  aspect_ratio?: unknown;
  num_outputs?: unknown;
  image?: unknown;
  mask?: unknown;
  retry_of?: unknown;
}

interface JobRow {
  id: string;
  user_id: string;
  operation: string;
  status: "queued" | "processing" | "completed" | "failed" | "cancelled";
  endpoint: string | null;
  status_url: string | null;
  response_url: string | null;
  cancel_url: string | null;
  outputs: fal.Output[] | null;
  error_code: string | null;
  error_message: string | null;
  created_at: string;
}

const safety = safetyConfig();
console.info(`output check in force: ${outputCheck()}${safety ? ` + ${safety.provider}:${safety.model}` : ""}`);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const db = serviceClient();
    const user = await requireUser(db, req);
    const url = new URL(req.url);
    const jobId = url.searchParams.get("job_id");

    switch (req.method) {
      case "POST": {
        const entitlement = await resolveEntitlement(db, user.id, req.headers.get("x-entitlement-jws"));
        const install = await verifyInstall(req.headers.get("x-app-transaction"));
        return await createJob(db, user.id, entitlement, install, clientIp(req.headers), req);
      }
      case "GET": {
        if (jobId) return await pollJob(db, user.id, jobId, waitSeconds(url.searchParams.get("wait")), req.signal);
        await resolveEntitlement(db, user.id, req.headers.get("x-entitlement-jws"));
        const install = await verifyInstall(req.headers.get("x-app-transaction"));
        return json(await walletState(db, user.id, install, clientIp(req.headers)));
      }
      case "DELETE":
        if (!jobId) throw new HttpError(400, "bad_request", "Missing job_id.");
        return await cancelJob(db, user.id, jobId, url.searchParams.get("intent") === "cancel");
      default:
        throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    }
  } catch (error) {
    return errorResponse(error);
  }
});

// MARK: - Create

/** Reads the body, refusing anything over MAX_BODY_BYTES even without a Content-Length. */
async function readBody(req: Request): Promise<GenerationRequest> {
  const tooLarge = () => new HttpError(413, "too_large", "That photo is too large. Try a smaller one.");
  if (Number(req.headers.get("content-length") ?? "0") > MAX_BODY_BYTES) throw tooLarge();
  const chunks: Uint8Array[] = [];
  let size = 0;
  const reader = req.body?.getReader();
  while (reader) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      throw tooLarge();
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpError(400, "bad_request", "Invalid JSON body.");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new HttpError(400, "bad_request", "Invalid JSON body.");
  }
  return body as GenerationRequest;
}

/** A photo or mask the server accepts (type, size, dimensions), or the reason it doesn't. */
function requireImage(value: unknown, missing: string): string {
  if (value === undefined || value === null || value === "") throw new HttpError(400, "bad_request", missing);
  const check = checkImage(value);
  if (!check.ok) {
    console.warn("image rejected:", check.reason);
    if (check.code === "too_large") {
      throw new HttpError(413, "too_large", "That photo is too large. Try a smaller one.");
    }
    throw new HttpError(400, "image_invalid", "This photo couldn't be read. Try another one.");
  }
  return value as string;
}

function optionalString(value: unknown, maxLength: number): string | undefined {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength ? value : undefined;
}

async function createJob(
  db: SupabaseClient,
  userId: string,
  entitlement: EntitlementStatus,
  install: InstallProof,
  ip: string | undefined,
  req: Request,
): Promise<Response> {
  const body = await readBody(req);
  const isPro = entitlement.isPro;

  const operation = typeof body.operation === "string" ? body.operation : "";
  if (!fal.OPERATIONS.has(operation)) throw new HttpError(400, "bad_request", "Unknown operation.");
  const op = operation as fal.Operation;
  const numOutputs = typeof body.num_outputs === "number" ? Math.trunc(body.num_outputs) : 1;
  if (numOutputs < 1 || numOutputs > MAX_OUTPUTS) {
    throw new HttpError(400, "bad_request", "You can create 1–4 images at a time.");
  }
  if (numOutputs > 1 && !isPro) {
    throw new HttpError(402, "pro_required", "Creating several images at once is a Pro feature.");
  }
  const image = op !== "text_to_image" ? requireImage(body.image, "Pick a photo first.") : undefined;
  const mask = op === "erase_object" ? requireImage(body.mask, "Brush over what you want to erase.") : undefined;
  const styleId = optionalString(body.style_id, 100);
  if (styleId && PRO_STYLES.has(styleId) && !isPro) {
    throw new HttpError(402, "pro_required", "This style is part of Pro.");
  }
  const templateId = optionalString(body.template_id, 100);
  if (
    body.retry_of !== undefined && body.retry_of !== null &&
    (typeof body.retry_of !== "string" || !UUID_PATTERN.test(body.retry_of))
  ) {
    throw new HttpError(400, "bad_request", "Invalid retry.");
  }
  const retryOf = typeof body.retry_of === "string" ? body.retry_of : null;

  const useXAI = provider() === "xai";
  if (useXAI && !xai.supports(op)) throw new HttpError(400, "bad_request", "Background removal runs on your device.");

  const raw = typeof body.prompt === "string" ? body.prompt : "";
  let prompt = sanitizePrompt(raw);
  if (promptLength(prompt) > MAX_PROMPT_CHARS) {
    throw new HttpError(400, "prompt_too_long", "That's a long description. Try a shorter one.");
  }
  let endpoint = useXAI ? `xai/${xai.model(op)}` : fal.ENDPOINTS[op];
  let verdict: Verdict;
  if (op === "restyle") {
    const recipe = templateRecipe(templateId ?? "");
    if (!recipe) {
      throw new HttpError(400, "bad_request", "This style is no longer available. Update the app to see the latest.");
    }
    if (recipe.isPro && !isPro) throw new HttpError(402, "pro_required", "This template is part of Pro.");
    prompt = recipe.prompt;
    if (!useXAI) endpoint = recipe.endpoint ?? endpoint;
    verdict = evaluatePrompt(prompt, op);
  } else {
    if ((op === "text_to_image" || op === "magic_edit") && !prompt) {
      throw new HttpError(400, "bad_request", "Describe what you want to see.");
    }
    // The raw text and what the provider would see: hidden characters fold
    // away in the first, the cleaned-up words show in the second.
    const first = evaluatePrompt(raw, op);
    verdict = first.allowed ? evaluatePrompt(prompt, op) : first;
  }
  // The app already appends the guard; this holds even for a modified client.
  // Restyle recipes carry their own identity clause, and enhance ignores the prompt.
  if (op === "magic_edit" && !prompt.endsWith(EDIT_GUARD)) prompt += EDIT_GUARD;

  const { data, error } = await db.rpc("admit_job", {
    p_user: userId,
    p_operation: op,
    p_endpoint: endpoint,
    p_template_id: templateId ?? null,
    p_outputs: numOutputs,
    p_input_images: op === "text_to_image" ? 0 : op === "erase_object" ? 2 : 1,
    p_retry_of: retryOf,
    p_app_transaction_id: install.status === "verified" ? install.appTransactionId ?? null : null,
    p_install_status: install.status,
    p_install_environment: install.status === "verified" ? install.environment : null,
    p_ip: ip ?? null,
    p_blocked_category: verdict.allowed ? null : verdict.category,
  });
  if (error || !data) {
    console.error("admit_job failed", error?.message);
    throw new HttpError(500, "internal", "Couldn't start the job.");
  }
  const admitted = data as AdmitResult;
  if (!admitted.ok || !admitted.job_id) throw admissionError(admitted, verdict.allowed ? undefined : verdict.reason);
  const jobId = admitted.job_id;

  const input: fal.JobInput = {
    operation: op,
    prompt,
    aspectRatio: typeof body.aspect_ratio === "string" && ASPECT_RATIOS.has(body.aspect_ratio)
      ? body.aspect_ratio
      : undefined,
    numOutputs,
    image,
    mask,
    isPro,
  };
  if (useXAI) {
    background(runXAI(db, jobId, input, await xai.userTag(userId)));
    return json({ job_id: jobId, status: "queued", credits_remaining: admitted.credits_remaining }, 202);
  }

  if (!await photoPassesSafetyCheck(db, jobId, input)) {
    return json({ job_id: jobId, status: "queued", credits_remaining: admitted.credits_remaining }, 202);
  }
  try {
    const queued = await fal.submit(endpoint, fal.buildFalInput(input));
    await db.from("jobs").update({
      fal_request_id: queued.request_id,
      status_url: queued.status_url,
      response_url: queued.response_url,
      cancel_url: queued.cancel_url,
      updated_at: new Date().toISOString(),
    }).eq("id", jobId);
  } catch (error) {
    await failJob(db, jobId, "provider_unavailable", "The AI service is busy. Your credit was refunded.");
    throw error;
  }

  return json({ job_id: jobId, status: "queued", credits_remaining: admitted.credits_remaining }, 202);
}

/** xAI answers in one request: mark the job processing, run it, keep the outcome. */
async function runXAI(db: SupabaseClient, jobId: string, input: fal.JobInput, userTag: string): Promise<void> {
  try {
    await db.from("jobs").update({ status: "processing", updated_at: new Date().toISOString() })
      .eq("id", jobId).eq("status", "queued");
    if (!await photoPassesSafetyCheck(db, jobId, input)) return;
    await finish(db, jobId, await xai.generate(input, userTag));
  } catch (error) {
    console.error("xai job failed", error);
    await failJob(db, jobId, "provider_failed", "This creation failed. Your credit was refunded.");
  }
}

/** Keeps work running after the response is sent (Supabase Edge Runtime). */
function background(work: Promise<void>): void {
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil(promise: Promise<unknown>): void } }).EdgeRuntime;
  if (runtime) {
    runtime.waitUntil(work);
  } else {
    work.catch((error) => console.error("background work failed", error));
  }
}

/** "xai" (the default when XAI_API_KEY is set) or "fal". */
function provider(): "xai" | "fal" {
  const chosen = Deno.env.get("AI_PROVIDER");
  if (chosen === "xai" || chosen === "fal") return chosen;
  return Deno.env.get("XAI_API_KEY") ? "xai" : "fal";
}

// MARK: - Safety model (ANTHROPIC_API_KEY, else XAI_SAFETY_MODEL; off without either)

async function classify(images: string[], subject: SafetySubject): Promise<SafetyVerdict | undefined> {
  const config = safetyConfig();
  if (!config) return undefined;
  const secret = API_KEY_SECRET[config.provider];
  const apiKey = Deno.env.get(secret);
  if (!apiKey) return { ok: false, reason: "check_failed", detail: `${secret} is not set` };
  return await classifyImages(images, subject, { ...config, apiKey });
}

/** The photo, before an edit spends anything at the image model. False when the job was stopped. */
async function photoPassesSafetyCheck(db: SupabaseClient, jobId: string, input: fal.JobInput): Promise<boolean> {
  if (!input.image) return true;
  const verdict = await classify([input.image], "photo");
  if (!verdict || verdict.ok) return true;
  console.warn(`photo check blocked job ${jobId}:`, verdict.reason === "flagged" ? verdict.categories : verdict.detail);
  if (verdict.reason === "flagged") {
    // Not a strike: a photo can be someone's ordinary holiday snap.
    await failJob(db, jobId, "input_blocked", "This photo can't be edited. Try another one. Your credit was refunded.");
  } else {
    // Its own code: no result exists yet, so the output check's "this result
    // wasn't shown" (safety_check_failed) would be the wrong thing to tell her.
    await failJob(db, jobId, "photo_check_failed", PHOTO_CHECK_FAILED);
  }
  return false;
}

// MARK: - Poll

async function pollJob(
  db: SupabaseClient,
  userId: string,
  jobId: string,
  wait: number,
  signal: AbortSignal,
): Promise<Response> {
  if (!UUID_PATTERN.test(jobId)) throw new HttpError(404, "not_found", "That job doesn't exist.");
  // One request for the whole wait instead of one every second or two.
  const fresh = await holdWhilePending(
    async () => {
      const job = await loadJob(db, userId, jobId);
      if (!isPending(job)) return job;
      await advance(db, job);
      return await loadJob(db, userId, jobId);
    },
    wait,
    { signal },
  );
  if (fresh.status === "completed") {
    // Handing the results over is what counts as delivered: results the app
    // never received are refunded (sweep_jobs()).
    const { data: outputs, error } = await db.rpc("deliver_outputs", { p_job: fresh.id, p_user: userId });
    if (error) {
      console.error("couldn't record the delivery", error.message);
    } else {
      fresh.outputs = Array.isArray(outputs) ? outputs as fal.Output[] : null;
    }
  }
  return json(await presentFinished(db, userId, fresh));
}

/** Moves a pending job forward by asking the provider (no webhook needed). */
async function advance(db: SupabaseClient, job: JobRow): Promise<void> {
  const timeout = job.endpoint?.startsWith("xai/") ? XAI_JOB_TIMEOUT_MS : JOB_TIMEOUT_MS;
  if (Date.now() - new Date(job.created_at).getTime() > timeout) {
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

  await finish(db, job.id, await fal.result(job.response_url));
}

const BLOCKED_RESULT = "This result was blocked by our safety filters. Your credit was refunded.";
const SAFETY_CHECK_FAILED = "Our safety check couldn't run, so this result wasn't shown. Your credit was refunded.";
const PHOTO_CHECK_FAILED = "We couldn't check this photo, so we didn't edit it. Your credit was refunded.";

/**
 * Stores a provider's outcome, then looks after the provider's credit
 * (provider-alerts.ts): a billing refusal pauses AI and tells the owner, and
 * a job the provider billed checks the estimated balance in the background.
 */
async function finish(db: SupabaseClient, jobId: string, outcome: fal.ResultOutcome): Promise<void> {
  await store(db, jobId, outcome);
  if (!outcome.ok && outcome.code === "provider_billing") await pauseForProviderBilling(db);
  else if (outcome.ok || outcome.code === "content_blocked") runInBackground(checkProviderBudget(db));
}

/** Stores a provider's outcome: results (after the output safety checks) or a refund. */
async function store(db: SupabaseClient, jobId: string, outcome: fal.ResultOutcome): Promise<void> {
  if (!outcome.ok) {
    // The provider's own moderation withheld it: a strike, like a flag below.
    if (outcome.code === "content_blocked") await flagJob(db, jobId, outcome.message, "provider_moderation");
    else await failJob(db, jobId, outcome.code, outcome.message);
    return;
  }
  const verdict = await checkOutputs(outcome.outputs, outcome.moderatedBy);
  if (!verdict.ok) {
    console.warn(`output check (${verdict.check}) blocked job ${jobId}: ${verdict.reason}`);
    if (verdict.reason === "flagged") await flagJob(db, jobId, BLOCKED_RESULT, verdict.check);
    else await failJob(db, jobId, "safety_check_failed", SAFETY_CHECK_FAILED);
    return;
  }
  const second = await classify(
    outcome.outputs.map((output) =>
      output.url ?? `data:${output.content_type ?? "image/jpeg"};base64,${output.base64 ?? ""}`
    ),
    "result",
  );
  if (second && !second.ok) {
    console.warn(`safety model blocked job ${jobId}:`, second.reason === "flagged" ? second.categories : second.detail);
    if (second.reason === "flagged") {
      await flagJob(db, jobId, BLOCKED_RESULT, second.categories.join(",") || "safety_model");
    } else await failJob(db, jobId, "safety_check_failed", SAFETY_CHECK_FAILED);
    return;
  }
  await db.from("jobs")
    .update({ status: "completed", outputs: outcome.outputs, updated_at: new Date().toISOString() })
    .eq("id", jobId)
    .in("status", ["queued", "processing"]);
}

// MARK: - Cancel

/**
 * Cancels and refunds a job that is still running, or that finished without
 * its results ever reaching the app. On a delivered job a plain DELETE is the
 * app's "got it" (the results are cleared right away), and `giveUp` (the app
 * stopped waiting and never got them) settles it as the cleanup would.
 */
async function cancelJob(db: SupabaseClient, userId: string, jobId: string, giveUp: boolean): Promise<Response> {
  if (!UUID_PATTERN.test(jobId)) throw new HttpError(404, "not_found", "That job doesn't exist.");
  const job = await loadJob(db, userId, jobId);
  if ((job.status === "queued" || job.status === "processing") && job.cancel_url) await fal.cancel(job.cancel_url);
  const { data, error } = await db.rpc("cancel_job", { p_job: job.id, p_user: userId, p_cancel: giveUp });
  if (error || !data) throw new HttpError(500, "internal", "Something went wrong. Please try again.");
  const result = data as { status: JobRow["status"]; credits_remaining: number | null };
  if (result.status === "cancelled" || result.status === "completed") {
    return json({ job_id: job.id, status: result.status, credits_remaining: result.credits_remaining ?? undefined });
  }
  return json(await presentFinished(db, userId, await loadJob(db, userId, jobId)));
}

// MARK: - Helpers

/**
 * The balance. The address is the one admit_job gets, so a cool-down or block
 * kept on it (an install without a verified App Store transaction) shows here too.
 */
async function walletState(
  db: SupabaseClient,
  userId: string,
  install: InstallProof,
  ip: string | undefined,
): Promise<unknown> {
  const { data, error } = await db.rpc("wallet_state", {
    p_user: userId,
    p_app_transaction_id: install.status === "verified" ? install.appTransactionId ?? null : null,
    p_install_status: install.status,
    p_install_environment: install.status === "verified" ? install.environment : null,
    p_ip: ip ?? null,
  });
  if (error || !data) {
    console.error("wallet_state failed", error?.message);
    throw new HttpError(500, "internal", "Couldn't load your credits. Please try again.");
  }
  return data;
}

async function loadJob(db: SupabaseClient, userId: string, jobId: string): Promise<JobRow> {
  const { data } = await db.from("jobs").select("*").eq("id", jobId).eq("user_id", userId).maybeSingle();
  if (!data) throw new HttpError(404, "not_found", "That job doesn't exist.");
  return data as JobRow;
}

/**
 * Marks a pending job failed and refunds it, in one step (fail_job()), so a
 * background task cut off halfway can't leave a failed job unrefunded.
 */
async function failJob(db: SupabaseClient, jobId: string, code: string, message: string): Promise<void> {
  const { error } = await db.rpc("fail_job", { p_job: jobId, p_code: code, p_message: message });
  if (error) console.error("fail_job failed", error.message);
}

/** A result the moderation flagged: failed, refunded and counted as a strike (flag_job()). */
async function flagJob(db: SupabaseClient, jobId: string, message: string, category: string): Promise<void> {
  const { error } = await db.rpc("flag_job", {
    p_job: jobId,
    p_code: "content_blocked",
    p_message: message,
    p_category: category,
  });
  if (error) {
    console.error("flag_job failed", error.message);
    await failJob(db, jobId, "content_blocked", message);
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

/** A finished job also carries the balance, so the app shows the charge or the refund at once. */
async function presentFinished(db: SupabaseClient, userId: string, job: JobRow): Promise<Record<string, unknown>> {
  const body = present(job);
  if (job.status === "completed" || job.status === "failed" || job.status === "cancelled") {
    // The stored balance with the job's install, without refreshing anything:
    // a poll carries no proof of Pro or of the install.
    const { data, error } = await db.rpc("job_balance", { p_job: job.id, p_user: userId });
    if (!error && typeof data === "number") body.credits_remaining = data;
  }
  return body;
}
