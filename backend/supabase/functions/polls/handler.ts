// "Which vibe?" polls with friends: what every route does, with the database,
// Apple, Claude and the clock behind `PollsDeps`, so handler_test.ts runs it
// without any of them. Contract: backend/README.md, "Polls"; SQL:
// 20261102000000_polls.sql.
//
// Base /functions/v1/polls, JWT verification on at the gateway: the app sends
// her session, the poll page (aybuke.org/p/<id>) the public anon key.
//
//   POST   /polls                 her session   create → 201 { poll_id, share_url, expires_at, remaining_today }
//   GET    /polls?id=             anyone        the poll (+ X-Poll-Voter) → { …, images, votes once voted }
//   GET    /polls/image?…&sig=    anyone        one picture (a signed URL from GET /polls) → image/jpeg
//   POST   /polls/vote            anyone        { poll_id, choice, voter } → { votes, my_vote }
//   POST   /polls/report          anyone        { poll_id, reason } → { reported, taken_down }
//   GET    /polls/mine            her session   her polls that haven't ended → { polls, remaining_today, daily_cap }
//   DELETE /polls?id=             her session   deletes it now → { deleted: true }
//
// Logs carry the route, the outcome, counts and timings: never a question, a
// picture, a poll id, a voter code or an address.
import { ADMISSION_MESSAGES } from "../_shared/admission.ts";
import type { InstallProof } from "../_shared/apple.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";
import { sanitizePrompt } from "../_shared/input.ts";
import { evaluatePrompt, type Verdict } from "../_shared/policy.ts";
import { isServiceFailure, type SafetyVerdict } from "../_shared/safety.ts";
import { dataUri, preparePicture, type Screened, screenPicture } from "./picture.ts";
import { checkPictureUrl, pictureUrl, POLL_ID_PATTERN, signingKey, urlExpiry } from "./signing.ts";

export const SHARE_BASE = "https://aybuke.org/p/";
/** Her words, in characters (grapheme clusters, as the app counts them). */
export const MAX_QUESTION = 80;
/** Two pictures of at most 1.5 MB as base64, the question and the JSON around them. */
export const MAX_CREATE_BODY = 4_718_592;
const MAX_SMALL_BODY = 4_096;
const VOTER_PATTERN = /^[A-Za-z0-9_-]{16,128}$/;
export const REPORT_REASONS = ["sexual", "minor", "bullying", "privacy", "harmful", "other"] as const;

/** The app's languages, as the contract spells them. */
export const LOCALES = ["en", "tr", "es", "pt-BR", "fr", "de", "it", "ru", "ja", "ko", "zh-Hans", "id"];

/** Preflight: the voter header too, and browsers may keep the answer for a day. */
export const PREFLIGHT_HEADERS: Record<string, string> = {
  ...corsHeaders,
  "Access-Control-Allow-Headers": `${corsHeaders["Access-Control-Allow-Headers"]}, x-poll-voter`,
  "Access-Control-Max-Age": "86400",
};

export interface RpcResult {
  data: unknown;
  error: { message: string } | null;
}

export interface PollsDeps {
  /** A database function, with the service role. */
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResult>;
  /** Her session, or a 401 HttpError. */
  requireUser(req: Request): Promise<{ id: string }>;
  /** The user behind a session, or null for the anon key; never throws. */
  sessionUser(req: Request): Promise<string | null>;
  verifyInstall(jws: string | null): Promise<InstallProof>;
  /** The independent safety check of one picture (a data URI); undefined while Claude isn't set up. */
  checkPicture?: (picture: string) => Promise<SafetyVerdict>;
  /** The key for picture URLs (the service role key). */
  signingSecret: string;
  /** https://<project>.supabase.co/functions/v1/polls */
  publicBase: string;
  /** The caller's address bucket (clientIp() in _shared/input.ts). */
  clientIp(req: Request): string | undefined;
  now(): Date;
  /** Counts and timings only. */
  log(entry: Record<string, unknown>): void;
}

/** What the SQL functions answer when they refuse. */
interface Refusal {
  ok: false;
  code: string;
  status: number;
  retry_after?: number;
  until?: string;
  category?: string;
}

const MESSAGES: Record<string, string> = {
  not_found: "This poll has ended or was removed.",
  bad_request: "That request doesn't look right.",
  rate_limited: "Too many requests. Please try again a little later.",
  safety_unavailable: "Polls are taking a short break. Please try again later.",
  install_blocked: ADMISSION_MESSAGES.install_blocked,
  cooldown: ADMISSION_MESSAGES.cooldown,
  url_expired: "This picture link has expired. Open the poll again.",
  image_blocked: "This picture can't be shared in a poll. Try another one.",
  image_invalid: "We couldn't read this picture. Try another one.",
  too_large: "This picture is too large. Try a smaller one.",
  content_blocked: "This question isn't allowed. Try asking about the vibe.",
  internal: "Something went wrong. Please try again.",
};

const fail = (status: number, code: string, extra: Record<string, unknown> = {}, retryAfter?: number) =>
  new HttpError(status, code, MESSAGES[code] ?? MESSAGES.internal, undefined, retryAfter, extra);

function refusal(result: Refusal): HttpError {
  const extra: Record<string, unknown> = {};
  if (result.until) extra.until = result.until;
  return fail(result.status, result.code, extra, result.retry_after);
}

async function call(deps: PollsDeps, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const { data, error } = await deps.rpc(fn, args);
  if (error || !data || typeof data !== "object") {
    console.error(`${fn} failed`, error?.message);
    throw fail(500, "internal");
  }
  const result = data as Record<string, unknown>;
  if (result.ok === false) throw refusal(result as unknown as Refusal);
  return result;
}

// MARK: - Requests

const SEGMENTER = typeof Intl.Segmenter === "function"
  ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
  : undefined;

/** Characters as the app counts them (grapheme clusters; code points without ICU). */
export function textLength(text: string): number {
  return SEGMENTER ? [...SEGMENTER.segment(text)].length : [...text].length;
}

/** The contract's code for a language tag; English for anything else. */
export function normalizeLocale(value: unknown): string {
  if (typeof value !== "string") return "en";
  const tag = value.trim().replaceAll("_", "-").toLowerCase();
  const exact = LOCALES.find((code) => code.toLowerCase() === tag);
  if (exact) return exact;
  const language = tag.split("-")[0];
  if (language === "pt") return "pt-BR";
  if (language === "zh") return "zh-Hans";
  return LOCALES.find((code) => code === language) ?? "en";
}

/** The body as text, refusing more than `maxBytes` even without a Content-Length. */
export async function readBody(req: Request, maxBytes: number, tooLarge: () => HttpError): Promise<string> {
  if (Number(req.headers.get("content-length") ?? "0") > maxBytes) throw tooLarge();
  const chunks: Uint8Array[] = [];
  let size = 0;
  const reader = req.body?.getReader();
  while (reader) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
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
  return new TextDecoder().decode(bytes);
}

async function readJson(req: Request, maxBytes: number, tooLarge: () => HttpError): Promise<Record<string, unknown>> {
  const text = await readBody(req, maxBytes, tooLarge);
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw fail(400, "bad_request");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) throw fail(400, "bad_request");
  return body as Record<string, unknown>;
}

export interface CreateRequest {
  question: string | null;
  /** The question as sent, for the policy (it also checks what sanitizing removed). */
  rawQuestion: string;
  pictures: [Screened, Screened];
  locale: string;
}

/** Invisible characters that can hide or reorder text; ZWJ and variation selectors stay (emoji need them). */
const HIDDEN =
  /[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF\uFFF9-\uFFFB]|\u{E0000}|[\u{E0001}-\u{E007F}]/gu;
/** Code points a question may have: 80 characters, even long emoji sequences. */
const MAX_QUESTION_CODE_POINTS = 800;

/**
 * Her question as friends will read it: NFC, line breaks and other control
 * characters as spaces, hidden direction and zero-width characters removed,
 * whitespace collapsed. Unlike a prompt (sanitizePrompt), emoji keep their
 * joiners and variation selectors, so 👩‍👩‍👧 and ❤️ look as she typed them.
 */
export function cleanQuestion(raw: string): string {
  return raw.normalize("NFC")
    .replace(/\p{Cc}/gu, " ")
    .replace(HIDDEN, "")
    .replace(/\s+/gu, " ")
    .trim();
}

/** The create body as the contract has it: 400, 413 or 422 otherwise. */
export function parseCreate(body: Record<string, unknown>): CreateRequest {
  const { images, question, locale } = body;
  if (!Array.isArray(images) || images.length !== 2) throw fail(400, "bad_request");
  if (question !== undefined && question !== null && typeof question !== "string") throw fail(400, "bad_request");
  const rawQuestion = typeof question === "string" ? question : "";
  const cleaned = cleanQuestion(rawQuestion);
  if (textLength(cleaned) > MAX_QUESTION || [...cleaned].length > MAX_QUESTION_CODE_POINTS) {
    throw new HttpError(400, "bad_request", "That's a long question. Try a shorter one.");
  }
  const pictures = images.map((image, index) => {
    const side = index === 0 ? "a" : "b";
    const screened = screenPicture(image);
    if (!screened.ok) {
      throw screened.code === "too_large" ? fail(413, "too_large", { side }) : fail(422, "image_invalid", { side });
    }
    return screened;
  }) as [Screened, Screened];
  return { question: cleaned || null, rawQuestion, pictures, locale: normalizeLocale(locale) };
}

/**
 * Her question against the prompt policy, with an edit's rules (no rating
 * looks): as sent, as shown, and as a prompt would be cleaned up.
 */
export function screenQuestion(request: Pick<CreateRequest, "question" | "rawQuestion">): Verdict {
  for (const text of [request.rawQuestion, request.question, sanitizePrompt(request.rawQuestion)]) {
    if (!text) continue;
    const verdict = evaluatePrompt(text, "magic_edit");
    if (!verdict.allowed) return verdict;
  }
  return { allowed: true };
}

function pollId(value: string | null | undefined): string {
  if (!value || !POLL_ID_PATTERN.test(value)) throw fail(400, "bad_request");
  return value;
}

function installArgs(install: InstallProof) {
  return {
    p_app_transaction_id: install.status === "verified" ? install.appTransactionId ?? null : null,
    p_install_status: install.status,
  };
}

// MARK: - Routes

async function create(req: Request, deps: PollsDeps): Promise<Response> {
  const started = Date.now();
  const entry: Record<string, unknown> = { fn: "polls", route: "create" };
  const done = (outcome: string, extra: Record<string, unknown> = {}) =>
    deps.log({ ...entry, outcome, ms: Date.now() - started, ...extra });

  const user = await deps.requireUser(req);
  const body = await readJson(req, MAX_CREATE_BODY, () => fail(413, "too_large"));
  const request = parseCreate(body);
  const verdict = screenQuestion(request);
  const install = await deps.verifyInstall(req.headers.get("x-app-transaction"));
  const ip = deps.clientIp(req) ?? null;
  const attempt = { p_user: user.id, ...installArgs(install), p_ip: ip };

  let admitted: Record<string, unknown>;
  try {
    admitted = await call(deps, "admit_poll", {
      ...attempt,
      p_blocked_category: verdict.allowed ? null : verdict.category,
    });
  } catch (error) {
    if (error instanceof HttpError && error.code === "content_blocked" && !verdict.allowed) {
      done("blocked_question", { category: verdict.category });
      throw new HttpError(422, "content_blocked", verdict.reason, undefined, undefined, {
        category: verdict.category,
      });
    }
    if (error instanceof HttpError) done("refused", { code: error.code });
    throw error;
  }

  const finish = async (outcome: "image_blocked" | "image_invalid" | "unavailable") => {
    const { error } = await deps.rpc("finish_poll_attempt", { ...attempt, p_outcome: outcome });
    if (error) console.error("finish_poll_attempt failed", error.message);
  };

  if (!deps.checkPicture) {
    await finish("unavailable");
    done("unavailable", { detail: "no safety check" });
    throw fail(503, "safety_unavailable");
  }

  const pictures = [];
  for (const [index, screened] of request.pictures.entries()) {
    const prepared = await preparePicture(screened);
    if (!prepared.ok) {
      await finish("image_invalid");
      done("image_invalid", { side: index === 0 ? "a" : "b", detail: prepared.reason });
      throw fail(422, "image_invalid", { side: index === 0 ? "a" : "b" });
    }
    pictures.push(prepared.picture);
  }
  const prepareMs = Date.now() - started;

  const uris = pictures.map(dataUri);
  const verdicts = await Promise.all(uris.map((uri) => deps.checkPicture!(uri)));
  const sides = verdicts.flatMap((v, index) => !v.ok && !isServiceFailure(v) ? [index === 0 ? "a" : "b"] : []);
  if (sides.length > 0) {
    await finish("image_blocked");
    done("image_blocked", {
      sides,
      // A short reason per side: the categories, or "refused" when Claude wouldn't look.
      detail: verdicts.map((v) => v.ok ? "ok" : v.reason === "flagged" ? v.categories.join("+") : v.detail),
    });
    throw fail(422, "image_blocked", { sides });
  }
  const failure = verdicts.find((v) => !v.ok);
  if (failure && !failure.ok) {
    await finish("unavailable");
    done("unavailable", { detail: failure.reason === "check_failed" ? failure.detail : failure.reason });
    throw fail(503, "safety_unavailable");
  }

  const { data, error } = await deps.rpc("create_poll", {
    p_user: user.id,
    p_question: request.question,
    p_locale: request.locale,
    p_image_a: uris[0].slice(uris[0].indexOf(",") + 1),
    p_image_b: uris[1].slice(uris[1].indexOf(",") + 1),
    p_a_width: pictures[0].width,
    p_a_height: pictures[0].height,
    p_b_width: pictures[1].width,
    p_b_height: pictures[1].height,
    p_app_transaction_id: attempt.p_app_transaction_id,
    p_install_status: attempt.p_install_status,
  });
  const created = data as { poll_id?: string; expires_at?: string } | null;
  if (error || !created?.poll_id) {
    console.error("create_poll failed", error?.message);
    await finish("unavailable");
    done("unavailable", { detail: "store failed" });
    throw fail(500, "internal");
  }
  done("created", {
    prepare_ms: prepareMs,
    kb: pictures.map((p) => Math.round(p.jpeg.length / 1024)),
    question: request.question !== null,
    locale: request.locale,
  });
  return json({
    poll_id: created.poll_id,
    share_url: SHARE_BASE + created.poll_id,
    expires_at: created.expires_at,
    remaining_today: admitted.remaining_today,
  }, 201);
}

async function view(req: Request, deps: PollsDeps, url: URL): Promise<Response> {
  const id = pollId(url.searchParams.get("id"));
  const voterHeader = req.headers.get("x-poll-voter")?.trim() ?? "";
  const voter = VOTER_PATTERN.test(voterHeader) ? voterHeader : null;
  const user = await deps.sessionUser(req);
  const poll = await call(deps, "poll_view", {
    p_poll: id,
    p_voter: voter,
    p_user: user,
    p_ip: deps.clientIp(req) ?? null,
  });
  const now = deps.now();
  const expires = urlExpiry(now, new Date(String(poll.expires_at)));
  const key = await signingKey(deps.signingSecret);
  return json(
    {
      poll_id: id,
      question: poll.question ?? null,
      locale: poll.locale,
      created_at: poll.created_at,
      expires_at: poll.expires_at,
      images: {
        a: await pictureUrl(key, deps.publicBase, id, "a", expires),
        b: await pictureUrl(key, deps.publicBase, id, "b", expires),
      },
      image_sizes: poll.sizes,
      urls_expire_at: new Date(expires * 1000).toISOString(),
      is_creator: poll.is_creator === true,
      my_vote: poll.my_vote ?? null,
      votes: poll.votes ?? null,
    },
    200,
    { "Cache-Control": "no-store" },
  );
}

async function picture(req: Request, deps: PollsDeps, url: URL): Promise<Response> {
  const now = deps.now();
  const checked = await checkPictureUrl(await signingKey(deps.signingSecret), url.searchParams, now);
  if (!checked.ok) {
    throw checked.reason === "malformed" ? fail(400, "bad_request") : fail(403, "url_expired");
  }
  const result = await call(deps, "poll_image", {
    p_poll: checked.pollId,
    p_side: checked.side,
    p_ip: deps.clientIp(req) ?? null,
  });
  const binary = atob(String(result.image ?? ""));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  const maxAge = Math.max(0, checked.expires - Math.floor(now.getTime() / 1000));
  return new Response(bytes, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "image/jpeg",
      "Content-Length": String(bytes.length),
      // Only the visitor's browser keeps it, and never past the URL's end.
      "Cache-Control": `private, max-age=${maxAge}`,
      "X-Content-Type-Options": "nosniff",
      "Cross-Origin-Resource-Policy": "cross-origin",
    },
  });
}

async function vote(req: Request, deps: PollsDeps): Promise<Response> {
  const body = await readJson(req, MAX_SMALL_BODY, () => fail(400, "bad_request"));
  const id = pollId(typeof body.poll_id === "string" ? body.poll_id : null);
  const choice = body.choice;
  const voter = body.voter;
  if ((choice !== "a" && choice !== "b") || typeof voter !== "string" || !VOTER_PATTERN.test(voter)) {
    throw fail(400, "bad_request");
  }
  const result = await call(deps, "cast_poll_vote", {
    p_poll: id,
    p_voter: voter,
    p_choice: choice,
    p_ip: deps.clientIp(req) ?? null,
  });
  return json({ votes: result.votes, my_vote: result.my_vote });
}

async function report(req: Request, deps: PollsDeps): Promise<Response> {
  const body = await readJson(req, MAX_SMALL_BODY, () => fail(400, "bad_request"));
  const id = pollId(typeof body.poll_id === "string" ? body.poll_id : null);
  const reason = body.reason;
  if (typeof reason !== "string" || !(REPORT_REASONS as readonly string[]).includes(reason)) {
    throw fail(400, "bad_request");
  }
  const result = await call(deps, "report_poll", { p_poll: id, p_reason: reason, p_ip: deps.clientIp(req) ?? null });
  deps.log({ fn: "polls", route: "report", reason, taken_down: result.taken_down === true });
  return json({ reported: true, taken_down: result.taken_down === true });
}

async function mine(req: Request, deps: PollsDeps): Promise<Response> {
  const user = await deps.requireUser(req);
  const install = await deps.verifyInstall(req.headers.get("x-app-transaction"));
  const result = await call(deps, "my_polls", { p_user: user.id, ...installArgs(install) });
  const polls = Array.isArray(result.polls) ? result.polls as Record<string, unknown>[] : [];
  return json(
    {
      polls: polls.map((poll) => ({ ...poll, share_url: SHARE_BASE + String(poll.poll_id) })),
      remaining_today: result.remaining_today,
      daily_cap: result.daily_cap,
    },
    200,
    { "Cache-Control": "no-store" },
  );
}

async function remove(req: Request, deps: PollsDeps, url: URL): Promise<Response> {
  const user = await deps.requireUser(req);
  const id = pollId(url.searchParams.get("id"));
  const result = await call(deps, "delete_poll", { p_poll: id, p_user: user.id });
  if (result.deleted !== true) throw fail(404, "not_found");
  deps.log({ fn: "polls", route: "delete", outcome: "deleted" });
  return json({ deleted: true });
}

async function route(req: Request, deps: PollsDeps): Promise<Response> {
  const url = new URL(req.url);
  const name = url.pathname.replace(/\/+$/, "").split("/").pop();
  switch (`${req.method} ${name}`) {
    case "POST polls":
      return await create(req, deps);
    case "GET polls":
      return await view(req, deps, url);
    case "DELETE polls":
      return await remove(req, deps, url);
    case "GET image":
      return await picture(req, deps, url);
    case "POST vote":
      return await vote(req, deps);
    case "POST report":
      return await report(req, deps);
    case "GET mine":
      return await mine(req, deps);
  }
  if (["polls", "image", "vote", "report", "mine"].includes(name ?? "")) {
    throw new HttpError(405, "method_not_allowed", "Method not allowed.");
  }
  throw fail(404, "not_found");
}

export async function handlePolls(req: Request, deps: PollsDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: PREFLIGHT_HEADERS });
  try {
    return await route(req, deps);
  } catch (error) {
    return errorResponse(error);
  }
}
