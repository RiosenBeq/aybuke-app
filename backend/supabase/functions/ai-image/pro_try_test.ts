// deno test ai-image/
// ai-image's gate for Pro looks and styles (migration 20261101000000): the
// steps createJob() takes, from the Pro check to admission, against an
// in-memory stand-in for private.ad_unlocks that answers the calls ai-image
// makes the way the SQL does (ad_unlock_available(), then admit_unlocked_job()
// or admit_job()). The SQL itself is tested in
// backend/supabase/tests/rewarded_unlocks_test.sql.
import assert from "node:assert/strict";
import catalog from "../_shared/catalog.json" with { type: "json" };
import { ADMISSION_MESSAGES, admissionError, type AdmitResult } from "../_shared/admission.ts";
import { errorResponse, HttpError } from "../_shared/http.ts";
import { templateRecipe } from "../_shared/templates.ts";
import {
  admissionCall,
  PRO_REQUIRED,
  proItemsFor,
  requireUnlock,
  unlockChecker,
  type UnlockType,
} from "../_shared/unlocks.ts";

const SHE = "user-she";
const SOMEONE_ELSE = "user-else";
const [PRO_LOOK, OTHER_PRO_LOOK] = catalog.templates.filter((template) => template.isPro).map((template) =>
  template.id
);
const FREE_LOOK = catalog.templates.find((template) => !template.isPro)!.id;
const PRO_STYLE = catalog.proStyles[0];
const MINUTE = 60_000;

interface Try {
  user: string;
  type: UnlockType;
  id: string;
  expiresAt: number;
  jobId?: string;
}

/** private.ad_unlocks and the functions ai-image calls, on a clock. */
class TriesDatabase {
  now = 0;
  readonly tries: Try[] = [];
  readonly calls: { fn: string; args: Record<string, unknown> }[] = [];
  private jobs = 0;

  /** redeem_ad_reward() for a try's token: one try, 30 minutes from now. */
  grant(user: string, type: UnlockType, id: string): void {
    this.tries.push({ user, type, id, expiresAt: this.now + 30 * MINUTE });
  }

  /** release_credits(): a refunded job gives its try back. */
  refund(jobId: string): void {
    for (const t of this.tries) if (t.jobId === jobId) t.jobId = undefined;
  }

  rpc = (fn: string, args: Record<string, unknown>) => {
    this.calls.push({ fn, args });
    const same = (t: Try) => t.user === args.p_user && t.type === args.p_unlock_type && t.id === args.p_unlock_id;
    const live = (t: Try) => same(t) && !t.jobId && t.expiresAt > this.now;
    if (fn === "ad_unlock_available") {
      const data = args.p_retry_of
        ? this.tries.some((t) => same(t) && t.jobId === args.p_retry_of)
        : this.tries.some(live);
      return Promise.resolve({ data, error: null });
    }
    const jobId = `job-${++this.jobs}`;
    if (fn === "admit_unlocked_job") {
      const retried = args.p_retry_of && this.tries.some((t) => same(t) && t.jobId === args.p_retry_of);
      const spent = args.p_retry_of ? undefined : this.tries.filter(live).sort((a, b) => a.expiresAt - b.expiresAt)[0];
      if (!retried && !spent) {
        return Promise.resolve({ data: { ok: false, code: "pro_required", status: 402 }, error: null });
      }
      if (spent) spent.jobId = jobId;
    }
    return Promise.resolve({ data: { ok: true, job_id: jobId, credits_remaining: 1 }, error: null });
  };
}

interface JobRequest {
  isPro?: boolean;
  styleId?: string;
  templateId?: string;
  retryOf?: string;
}

/** The Pro check, as createJob() does it before anything else. */
function checkPro(db: TriesDatabase, user: string, request: JobRequest) {
  const recipe = request.templateId ? templateRecipe(request.templateId) : undefined;
  return requireUnlock(
    proItemsFor(request.isPro ?? false, request.styleId, recipe),
    request.retryOf ?? null,
    unlockChecker(db.rpc, user),
  );
}

/** Admission, as createJob() calls it once the prompt is settled. */
async function admit(
  db: TriesDatabase,
  user: string,
  request: JobRequest,
  unlock: Awaited<ReturnType<typeof checkPro>>,
) {
  const admission = admissionCall(unlock, {
    p_user: user,
    p_operation: request.templateId ? "restyle" : "text_to_image",
    p_endpoint: "test",
    p_template_id: request.templateId ?? null,
    p_retry_of: request.retryOf ?? null,
  });
  const { data } = await db.rpc(admission.fn, admission.args);
  const admitted = data as AdmitResult;
  if (!admitted.ok || !admitted.job_id) throw admissionError(admitted);
  return { fn: admission.fn, jobId: admitted.job_id };
}

async function startJob(db: TriesDatabase, user: string, request: JobRequest) {
  return await admit(db, user, request, await checkPro(db, user, request));
}

function proRequired(message: string) {
  return (error: unknown) => {
    assert.ok(error instanceof HttpError);
    assert.equal(error.status, 402);
    assert.equal(error.code, "pro_required");
    assert.equal(error.message, message);
    return true;
  };
}

Deno.test("admit without a try: a Pro look or style is 402 pro_required before anything is booked", async () => {
  const db = new TriesDatabase();
  await assert.rejects(startJob(db, SHE, { templateId: PRO_LOOK }), proRequired(PRO_REQUIRED.template));
  await assert.rejects(startJob(db, SHE, { styleId: PRO_STYLE }), proRequired(PRO_REQUIRED.style));
  assert.deepEqual(db.calls.map((call) => call.fn), ["ad_unlock_available", "ad_unlock_available"], "never admitted");
});

Deno.test("admit with a try of exactly that look: admit_unlocked_job spends it on the job", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", PRO_LOOK);
  const { fn, jobId } = await startJob(db, SHE, { templateId: PRO_LOOK });
  assert.equal(fn, "admit_unlocked_job");
  assert.deepEqual(db.calls[0], {
    fn: "ad_unlock_available",
    args: { p_user: SHE, p_unlock_type: "template", p_unlock_id: PRO_LOOK, p_retry_of: null },
  });
  assert.deepEqual(db.calls[1].args, {
    p_user: SHE,
    p_operation: "restyle",
    p_endpoint: "test",
    p_template_id: PRO_LOOK,
    p_retry_of: null,
    p_unlock_type: "template",
    p_unlock_id: PRO_LOOK,
  });
  assert.equal(db.tries[0].jobId, jobId, "spent with the job");

  db.grant(SHE, "style", PRO_STYLE);
  assert.equal((await startJob(db, SHE, { styleId: PRO_STYLE })).fn, "admit_unlocked_job", "a style works the same");
});

Deno.test("a wrong id doesn't count: another look, the other kind, someone else's try", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", OTHER_PRO_LOOK);
  db.grant(SOMEONE_ELSE, "template", PRO_LOOK);
  db.grant(SHE, "style", PRO_STYLE);
  await assert.rejects(startJob(db, SHE, { templateId: PRO_LOOK }), proRequired(PRO_REQUIRED.template));
  assert.ok(db.tries.every((t) => !t.jobId), "nothing spent");
});

Deno.test("an expired try doesn't count", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", PRO_LOOK);
  db.now += 31 * MINUTE;
  await assert.rejects(startJob(db, SHE, { templateId: PRO_LOOK }), proRequired(PRO_REQUIRED.template));
});

Deno.test("a spent try is spent; a refunded job gives it back for the rest of its 30 minutes", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", PRO_LOOK);
  const first = await startJob(db, SHE, { templateId: PRO_LOOK });
  await assert.rejects(startJob(db, SHE, { templateId: PRO_LOOK }), proRequired(PRO_REQUIRED.template), "consumed");

  db.now += 10 * MINUTE;
  db.refund(first.jobId);
  const second = await startJob(db, SHE, { templateId: PRO_LOOK });
  assert.equal(second.fn, "admit_unlocked_job", "refund restores the try");

  db.refund(second.jobId);
  db.now += 21 * MINUTE;
  await assert.rejects(startJob(db, SHE, { templateId: PRO_LOOK }), proRequired(PRO_REQUIRED.template), "ended");
});

Deno.test("a try that ends between the check and admission is refused by admission, never charged", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", PRO_LOOK);
  const unlock = await checkPro(db, SHE, { templateId: PRO_LOOK });
  db.now += 31 * MINUTE; // the prompt polish took long, say
  let refusal: unknown;
  try {
    await admit(db, SHE, { templateId: PRO_LOOK }, unlock);
  } catch (error) {
    refusal = error;
  }
  const response = errorResponse(refusal);
  assert.equal(response.status, 402);
  assert.deepEqual(await response.json(), {
    error: { code: "pro_required", message: ADMISSION_MESSAGES.pro_required },
  });
});

Deno.test("a free retry of a result a try paid for needs no new try", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", PRO_LOOK);
  const first = await startJob(db, SHE, { templateId: PRO_LOOK });
  const retry = await startJob(db, SHE, { templateId: PRO_LOOK, retryOf: first.jobId });
  assert.equal(retry.fn, "admit_unlocked_job");
  assert.equal(db.calls.at(-2)?.args.p_retry_of, first.jobId, "the check names the original job");
  assert.equal(db.tries[0].jobId, first.jobId, "the try stays with the original");
  await assert.rejects(
    startJob(db, SHE, { templateId: PRO_LOOK, retryOf: "job-no-try" }),
    proRequired(PRO_REQUIRED.template),
    "a retry of a job no try paid for",
  );
  await assert.rejects(
    startJob(db, SHE, { templateId: OTHER_PRO_LOOK, retryOf: first.jobId }),
    proRequired(PRO_REQUIRED.template),
    "a retry with another Pro look",
  );
});

Deno.test("Pro members and free looks never ask for a try", async () => {
  const db = new TriesDatabase();
  assert.equal((await startJob(db, SHE, { isPro: true, templateId: PRO_LOOK })).fn, "admit_job");
  assert.equal((await startJob(db, SHE, { isPro: true, styleId: PRO_STYLE })).fn, "admit_job");
  assert.equal((await startJob(db, SHE, { templateId: FREE_LOOK })).fn, "admit_job");
  assert.deepEqual(db.calls.map((call) => call.fn), ["admit_job", "admit_job", "admit_job"]);
  assert.ok(db.calls.every((call) => !("p_unlock_type" in call.args)), "admit_job's arguments as before");
});

Deno.test("one try covers one look or style, never two at once", async () => {
  const db = new TriesDatabase();
  db.grant(SHE, "template", PRO_LOOK);
  db.grant(SHE, "style", PRO_STYLE);
  await assert.rejects(
    startJob(db, SHE, { styleId: PRO_STYLE, templateId: PRO_LOOK }),
    proRequired(PRO_REQUIRED.style),
  );
  assert.equal(db.calls.length, 0, "refused without asking");
});

Deno.test("a check that fails is an error to retry, never a paywall", async () => {
  const check = unlockChecker(() => Promise.resolve({ data: null, error: { message: "connection reset" } }), SHE);
  await assert.rejects(
    requireUnlock([{ type: "template", id: PRO_LOOK }], null, check),
    (error: unknown) => error instanceof HttpError && error.status === 500 && error.code === "internal",
  );
  const odd = unlockChecker(() => Promise.resolve({ data: "yes", error: null }), SHE);
  assert.equal(await odd({ type: "template", id: PRO_LOOK }, null), false, "only true is a try");
});
