// deno test polls/
// Every route of /polls with a stubbed database, Apple and Claude: creating
// (each refusal, the safety check failing closed, the attempt given back when
// the check can't run), viewing with signed picture URLs, pictures, votes,
// reports, her list and deleting. One run goes through the real Anthropic SDK
// against a mocked fetch to check what Claude is sent.
import assert from "node:assert/strict";
import jpeg from "npm:jpeg-js@0.4.4";
import { claudeAnswer, claudeError, mockClaude, withoutEnv } from "../_shared/claude-mock.ts";
import type { InstallProof } from "../_shared/apple.ts";
import { HttpError } from "../_shared/http.ts";
import { classifyImages, type SafetyVerdict } from "../_shared/safety.ts";
import {
  cleanQuestion,
  handlePolls,
  MAX_QUESTION,
  normalizeLocale,
  type PollsDeps,
  type RpcResult,
  SHARE_BASE,
} from "./handler.ts";
import { base64, MAX_PICTURE_BYTES } from "./picture.ts";
import { checkPictureUrl, pictureUrl, signingKey, urlExpiry } from "./signing.ts";
import { jpegUri, makeJpeg, makePng, pngUri, withExif } from "./test_images.ts";

const BASE = "https://project.supabase.co/functions/v1/polls";
const SECRET = "service-role-key-for-tests";
const NOW = new Date("2026-10-16T10:20:00Z");
const POLL = "Ab3_Xy9-Kq2LmN0p";
const VOTER = "voterCode_abcdefghij";
const USER = "00000000-0000-0000-0000-00000000a11c";

type Rpc = (args: Record<string, unknown>) => unknown;

interface Options {
  rpc?: Record<string, Rpc | unknown>;
  user?: string | null;
  install?: InstallProof;
  check?: ((picture: string) => SafetyVerdict | Promise<SafetyVerdict>) | null;
  ip?: string;
}

const ok: SafetyVerdict = { ok: true };

function fake(options: Options = {}) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const checked: string[] = [];
  const logs: Record<string, unknown>[] = [];
  const defaults: Record<string, Rpc | unknown> = {
    admit_poll: { ok: true, remaining_today: 2 },
    finish_poll_attempt: null,
    create_poll: { poll_id: POLL, expires_at: "2026-10-17T10:20:00+00:00" },
    poll_view: {
      ok: true,
      poll_id: POLL,
      question: "Which vibe?",
      locale: "tr",
      created_at: "2026-10-16T09:00:00+00:00",
      expires_at: "2026-10-17T09:00:00+00:00",
      sizes: { a: { width: 540, height: 720 }, b: { width: 720, height: 540 } },
      is_creator: false,
      my_vote: null,
      votes: null,
    },
    poll_image: { ok: true, image: base64(makeJpeg(32, 24)), bytes: 0 },
    cast_poll_vote: { ok: true, votes: { a: 2, b: 1 }, my_vote: "a" },
    report_poll: { ok: true, reported: true, taken_down: false },
    my_polls: { polls: [], remaining_today: 3, daily_cap: 3 },
    delete_poll: { deleted: true },
  };
  const table = { ...defaults, ...options.rpc };
  const deps: PollsDeps = {
    rpc: (fn, args) => {
      calls.push({ fn, args });
      const entry = table[fn];
      let result: RpcResult;
      try {
        const data = typeof entry === "function" ? (entry as Rpc)(args) : entry;
        result = data instanceof Error ? { data: null, error: { message: data.message } } : { data, error: null };
      } catch (error) {
        result = { data: null, error: { message: String(error) } };
      }
      return Promise.resolve(result);
    },
    requireUser: (req) => {
      const user = options.user === undefined ? USER : options.user;
      const header = req.headers.get("Authorization") ?? "";
      if (!user || !header.includes("session")) {
        return Promise.reject(new HttpError(401, "unauthorized", "Missing session."));
      }
      return Promise.resolve({ id: user });
    },
    sessionUser: (req) => {
      const user = options.user === undefined ? USER : options.user;
      return Promise.resolve((req.headers.get("Authorization") ?? "").includes("session") ? user : null);
    },
    verifyInstall: () => Promise.resolve(options.install ?? { status: "missing" }),
    checkPicture: options.check === null ? undefined : async (picture) => {
      checked.push(picture);
      return options.check ? await options.check(picture) : ok;
    },
    signingSecret: SECRET,
    publicBase: BASE,
    clientIp: () => options.ip ?? "203.0.113.7",
    now: () => NOW,
    log: (entry) => logs.push(entry),
  };
  return { deps, calls, checked, logs, called: (fn: string) => calls.filter((c) => c.fn === fn) };
}

function request(
  method: string,
  path: string,
  init: { body?: unknown; session?: boolean; headers?: Record<string, string> } = {},
) {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${init.session ? "session-jwt" : "anon-key"}`);
  if (init.body !== undefined) headers.set("Content-Type", "application/json");
  return new Request(`https://project.supabase.co${path}`, {
    method,
    headers,
    body: init.body === undefined ? undefined : typeof init.body === "string" ? init.body : JSON.stringify(init.body),
  });
}

async function send(deps: PollsDeps, req: Request) {
  const response = await handlePolls(req, deps);
  const type = response.headers.get("Content-Type") ?? "";
  const body = type.includes("json") ? await response.json() : new Uint8Array(await response.arrayBuffer());
  return { status: response.status, headers: response.headers, body };
}

const pictureA = jpegUri(makeJpeg(1200, 900));
const pictureB = jpegUri(withExif(makeJpeg(960, 1280), 6));
const createBody = (extra: Record<string, unknown> = {}) => ({
  question: "  Which\nvibe   for Friday? ",
  images: [pictureA, pictureB],
  locale: "tr_TR",
  ...extra,
});

// MARK: - Create

Deno.test("create: re-encoded pictures, checked by Claude, stored; 201 with the link", async () => {
  const t = fake({ install: { status: "verified", appTransactionId: "txn-1", environment: "Sandbox" } });
  const result = await send(t.deps, request("POST", "/polls", { session: true, body: createBody() }));
  assert.equal(result.status, 201);
  assert.deepEqual(result.body, {
    poll_id: POLL,
    share_url: `${SHARE_BASE}${POLL}`,
    expires_at: "2026-10-17T10:20:00+00:00",
    remaining_today: 2,
  });
  assert.equal(SHARE_BASE, "https://aybuke.org/p/");

  const admit = t.called("admit_poll")[0].args;
  assert.deepEqual(admit, {
    p_user: USER,
    p_app_transaction_id: "txn-1",
    p_install_status: "verified",
    p_ip: "203.0.113.7",
    p_blocked_category: null,
  });
  assert.equal(t.checked.length, 2, "both pictures checked");
  assert.ok(t.checked.every((uri) => uri.startsWith("data:image/jpeg;base64,")));

  const stored = t.called("create_poll")[0].args;
  assert.equal(stored.p_question, "Which vibe for Friday?", "whitespace collapsed");
  assert.equal(stored.p_locale, "tr");
  // B is stored 960 × 1280 with orientation 6 (turn it clockwise): upright it's landscape.
  assert.deepEqual([stored.p_a_width, stored.p_a_height, stored.p_b_width, stored.p_b_height], [720, 540, 720, 540]);
  // What's stored is exactly what Claude saw, and it's a JPEG of that size.
  assert.equal(`data:image/jpeg;base64,${stored.p_image_a}`, t.checked[0]);
  assert.equal(`data:image/jpeg;base64,${stored.p_image_b}`, t.checked[1]);
  const b = jpeg.decode(Uint8Array.from(atob(String(stored.p_image_b)), (c) => c.charCodeAt(0)), { useTArray: true });
  assert.deepEqual([b.width, b.height], [720, 540], "B turned upright from its EXIF orientation");
  assert.equal(t.called("finish_poll_attempt").length, 0);
  assert.equal(stored.p_app_transaction_id, "txn-1");
  assert.deepEqual(stored.p_ai_sides, [], "no ai_sides: neither picture is labelled");

  const log = t.logs.find((entry) => entry.outcome === "created")!;
  assert.ok(log && typeof log.ms === "number" && Array.isArray(log.kb));
  assert.ok(!JSON.stringify(t.logs).includes("Friday") && !JSON.stringify(t.logs).includes(POLL), "no question, no id");
});

Deno.test("create: a PNG and no question; an unknown language becomes English", async () => {
  const png = pngUri(
    await makePng({
      width: 64,
      height: 48,
      colorType: 6,
      depth: 8,
      sample: (x) => [x * 3, 100, 200, x < 32 ? 0 : 255],
    }),
  );
  const t = fake();
  const result = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: { images: [png, pictureA], locale: "xx" } }),
  );
  assert.equal(result.status, 201);
  const stored = t.called("create_poll")[0].args;
  assert.equal(stored.p_question, null);
  assert.equal(stored.p_locale, "en");
  assert.deepEqual([stored.p_a_width, stored.p_a_height], [64, 48]);
  assert.deepEqual(t.called("admit_poll")[0].args.p_app_transaction_id, null);
});

Deno.test("create: needs her session", async () => {
  const t = fake({ user: null });
  const result = await send(t.deps, request("POST", "/polls", { session: false, body: createBody() }));
  assert.equal(result.status, 401);
  assert.equal(t.calls.length, 0);
});

Deno.test("create: 400 for a body outside the contract, before anything counts", async () => {
  const t = fake();
  const bad = [
    "not json",
    [],
    { images: [pictureA] },
    { images: [pictureA, pictureA, pictureA] },
    { images: "two" },
    { images: [pictureA, pictureB], question: 42 },
    { images: [pictureA, pictureB], question: "✨".repeat(MAX_QUESTION + 1) },
  ];
  for (const body of bad) {
    const result = await send(t.deps, request("POST", "/polls", { session: true, body }));
    assert.equal(result.status, 400, JSON.stringify(body).slice(0, 60));
    assert.equal(result.body.error.code, "bad_request");
  }
  const fine = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: createBody({ question: "👩‍👩‍👧".repeat(80) }) }),
  );
  assert.equal(fine.status, 201, "80 characters as she counts them (emoji included)");
  assert.equal(t.called("admit_poll").length, 1);
});

Deno.test("create: ai_sides says which pictures were edited with AI; anything else is 400 before counting", async () => {
  const cases: [unknown, string[]][] = [[["b"], ["b"]], [["b", "a"], ["a", "b"]], [[], []], [null, []]];
  for (const [aiSides, stored] of cases) {
    const t = fake();
    const result = await send(
      t.deps,
      request("POST", "/polls", { session: true, body: createBody({ ai_sides: aiSides }) }),
    );
    assert.equal(result.status, 201, JSON.stringify(aiSides));
    assert.deepEqual(t.called("create_poll")[0].args.p_ai_sides, stored, JSON.stringify(aiSides));
    assert.equal(t.logs.find((entry) => entry.outcome === "created")?.ai, stored.length, "the log counts them");
  }
  const t = fake();
  for (const aiSides of ["a", ["c"], ["A"], ["a", "a"], ["a", "b", "a"], [1], [null], {}, { a: true }, true]) {
    const result = await send(
      t.deps,
      request("POST", "/polls", { session: true, body: createBody({ ai_sides: aiSides }) }),
    );
    assert.equal(result.status, 400, JSON.stringify(aiSides));
    assert.equal(result.body.error.code, "bad_request");
  }
  assert.equal(t.calls.length, 0, "nothing admitted or counted");
});

Deno.test("create: 413 for a picture over 1.5 MB or a huge body, 422 image_invalid naming the side", async () => {
  const t = fake();
  const padded = new Uint8Array(MAX_PICTURE_BYTES + 3);
  padded.set(makeJpeg(32, 32));
  let result = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: createBody({ images: [pictureA, jpegUri(padded)] }) }),
  );
  assert.equal(result.status, 413);
  assert.deepEqual([result.body.error.code, result.body.error.side], ["too_large", "b"]);

  result = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: `{"images":["${"A".repeat(5_000_000)}"]}` }),
  );
  assert.equal(result.status, 413);

  const webp = `data:image/webp;base64,${base64(new Uint8Array(32))}`;
  result = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: createBody({ images: [webp, pictureB] }) }),
  );
  assert.equal(result.status, 422);
  assert.deepEqual([result.body.error.code, result.body.error.side], ["image_invalid", "a"]);
  assert.equal(t.calls.length, 0, "nothing admitted or counted");
});

Deno.test("create: a blocked question is counted at admission, answered 422, and never reaches Claude", async () => {
  const t = fake({
    rpc: {
      admit_poll: (args: Record<string, unknown>) => ({
        ok: false,
        code: "content_blocked",
        status: 422,
        category: args.p_blocked_category,
      }),
    },
  });
  const result = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: createBody({ question: "make me look sexy" }) }),
  );
  assert.equal(result.status, 422);
  assert.equal(result.body.error.code, "content_blocked");
  assert.equal(result.body.error.category, "sexual");
  assert.equal(t.called("admit_poll")[0].args.p_blocked_category, "sexual");
  assert.equal(t.checked.length, 0);
  assert.equal(t.called("create_poll").length, 0);
  // Rating looks: an edit's policy applies to the question.
  const rating = await send(
    fake({
      rpc: {
        admit_poll: (args: Record<string, unknown>) => ({
          ok: false,
          code: "content_blocked",
          status: 422,
          category: args.p_blocked_category,
        }),
      },
    }).deps,
    request("POST", "/polls", { session: true, body: createBody({ question: "which one makes me look skinnier" }) }),
  );
  assert.equal(rating.status, 422);
});

Deno.test("create: admission refusals pass through with their status and timing", async () => {
  const cases: [Record<string, unknown>, number, string][] = [
    [
      { ok: false, code: "rate_limited", status: 429, retry_after: 3600, until: "2026-10-17T00:00:00Z" },
      429,
      "rate_limited",
    ],
    [{ ok: false, code: "cooldown", status: 429, retry_after: 600, until: "2026-10-16T10:30:00Z" }, 429, "cooldown"],
    [{ ok: false, code: "install_blocked", status: 403 }, 403, "install_blocked"],
    [{ ok: false, code: "safety_unavailable", status: 503, retry_after: 120 }, 503, "safety_unavailable"],
  ];
  for (const [answer, status, code] of cases) {
    const t = fake({ rpc: { admit_poll: answer } });
    const result = await send(t.deps, request("POST", "/polls", { session: true, body: createBody() }));
    assert.equal(result.status, status, code);
    assert.equal(result.body.error.code, code);
    if (answer.retry_after) {
      assert.equal(result.headers.get("Retry-After"), String(answer.retry_after));
      assert.equal(result.body.error.retry_after, answer.retry_after);
    }
    if (answer.until) assert.equal(result.body.error.until, answer.until);
    assert.equal(t.checked.length, 0, "no Claude call after a refusal");
  }
  const broken = fake({ rpc: { admit_poll: new Error("connection reset") } });
  assert.equal((await send(broken.deps, request("POST", "/polls", { session: true, body: createBody() }))).status, 500);
});

Deno.test("create: without Claude no poll is made, and the attempt is given back", async () => {
  const t = fake({ check: null });
  const result = await send(t.deps, request("POST", "/polls", { session: true, body: createBody() }));
  assert.equal(result.status, 503);
  assert.equal(result.body.error.code, "safety_unavailable");
  assert.equal(t.called("finish_poll_attempt")[0].args.p_outcome, "unavailable");
  assert.equal(t.called("create_poll").length, 0);
});

Deno.test("create: a flagged or refused picture is image_blocked with its side; the attempt stays used", async () => {
  let n = 0;
  const t = fake({ check: () => n++ === 1 ? { ok: false, reason: "flagged", categories: ["nudity"] } : ok });
  let result = await send(t.deps, request("POST", "/polls", { session: true, body: createBody() }));
  assert.equal(result.status, 422);
  assert.deepEqual([result.body.error.code, result.body.error.sides], ["image_blocked", ["b"]]);
  assert.equal(t.called("finish_poll_attempt")[0].args.p_outcome, "image_blocked");
  assert.equal(t.called("create_poll").length, 0);
  assert.ok(JSON.stringify(t.logs).includes("nudity"), "the category is logged, nothing else");

  const refused = fake({ check: () => ({ ok: false, reason: "check_failed", detail: "refused" }) });
  result = await send(refused.deps, request("POST", "/polls", { session: true, body: createBody() }));
  assert.deepEqual([result.status, result.body.error.sides], [422, ["a", "b"]]);
  assert.equal(refused.called("finish_poll_attempt")[0].args.p_outcome, "image_blocked");
});

Deno.test("create: a check that couldn't run fails closed, 503, and gives the attempt back", async () => {
  let n = 0;
  const t = fake({
    check: () => n++ === 0 ? ok : { ok: false, reason: "check_failed", detail: "HTTP 529 overloaded_error" },
  });
  const result = await send(t.deps, request("POST", "/polls", { session: true, body: createBody() }));
  assert.equal(result.status, 503);
  assert.equal(result.body.error.code, "safety_unavailable");
  assert.equal(t.called("finish_poll_attempt")[0].args.p_outcome, "unavailable");
  assert.deepEqual(t.called("finish_poll_attempt")[0].args.p_user, USER);
  assert.equal(t.called("create_poll").length, 0);
});

Deno.test("create: a picture that can't be decoded after admission is image_invalid and counted", async () => {
  // A valid header with garbage after it: screened fine, decoding fails.
  const header = makeJpeg(64, 64).slice(0, 700);
  const broken = new Uint8Array(4000);
  broken.set(header);
  broken.fill(0xff, 700);
  const t = fake();
  const result = await send(
    t.deps,
    request("POST", "/polls", { session: true, body: createBody({ images: [pictureA, jpegUri(broken)] }) }),
  );
  if (result.status === 201) return; // jpeg-js may decode a damaged file tolerantly; then it's just a picture.
  assert.equal(result.status, 422);
  assert.deepEqual([result.body.error.code, result.body.error.side], ["image_invalid", "b"]);
  assert.equal(t.called("finish_poll_attempt")[0].args.p_outcome, "image_invalid");
});

Deno.test("create: storing fails → 500 and the attempt is given back", async () => {
  const t = fake({ rpc: { create_poll: new Error("insert failed") } });
  const result = await send(t.deps, request("POST", "/polls", { session: true, body: createBody() }));
  assert.equal(result.status, 500);
  assert.equal(t.called("finish_poll_attempt")[0].args.p_outcome, "unavailable");
});

Deno.test("create: Claude is asked about each picture alone, as a shared picture, through the real SDK", async () => {
  const claude = mockClaude(() => claudeAnswer({ flagged: false, categories: [] }));
  const options = { provider: "anthropic" as const, model: "claude-haiku-5-5", apiKey: "sk-test", fetcher: claude.fn };
  const t = fake();
  t.deps.checkPicture = (picture) => classifyImages([picture], "share", options);
  const result = await withoutEnv(() => send(t.deps, request("POST", "/polls", { session: true, body: createBody() })));
  assert.equal(result.status, 201);
  assert.equal(claude.calls.length, 2);
  for (const call of claude.calls) {
    const content = call.body.messages[0].content as { type: string; text?: string; source?: { media_type: string } }[];
    assert.equal(content.length, 2, "one picture per request");
    assert.equal(content[0].source?.media_type, "image/jpeg");
    assert.equal(content[1].text, "This is a picture someone wants to share with friends in a poll. Classify it.");
    assert.ok(call.body.system.includes("substances") && call.body.system.includes("weapons"), "checked like a result");
    const schema = call.body.output_config.format.schema as {
      properties: { categories: { items: { enum: string[] } } };
    };
    assert.ok(schema.properties.categories.items.enum.includes("weapons"));
    assert.ok(!JSON.stringify(call.body).includes("Friday"), "the question never goes to Claude");
  }

  const failing = mockClaude(() => claudeError(529, "overloaded_error"));
  const t2 = fake();
  t2.deps.checkPicture = (picture) =>
    classifyImages([picture], "share", { ...options, fetcher: failing.fn, maxRetries: 0 });
  const down = await withoutEnv(() => send(t2.deps, request("POST", "/polls", { session: true, body: createBody() })));
  assert.equal(down.status, 503);
});

// MARK: - View and pictures

Deno.test("view: the poll with signed picture URLs; no counts before voting", async () => {
  const t = fake();
  const result = await send(t.deps, request("GET", `/polls?id=${POLL}`, { headers: { "X-Poll-Voter": VOTER } }));
  assert.equal(result.status, 200);
  assert.equal(result.headers.get("Cache-Control"), "no-store");
  const body = result.body;
  assert.equal(body.question, "Which vibe?");
  assert.equal(body.locale, "tr");
  assert.equal(body.votes, null);
  assert.equal(body.my_vote, null);
  assert.equal(body.is_creator, false);
  assert.deepEqual(body.image_sizes, { a: { width: 540, height: 720 }, b: { width: 720, height: 540 } });
  assert.deepEqual(body.ai, { a: false, b: false }, "no labels unless the database says so");
  assert.deepEqual(t.called("poll_view")[0].args, { p_poll: POLL, p_voter: VOTER, p_user: null, p_ip: "203.0.113.7" });

  // URLs end on the next full hour but one (11:00 + 1 h = 12:00 UTC), and verify.
  assert.equal(body.urls_expire_at, "2026-10-16T12:00:00.000Z");
  const key = await signingKey(SECRET);
  for (const side of ["a", "b"]) {
    const url = new URL(body.images[side]);
    assert.equal(`${url.origin}${url.pathname}`, `${BASE}/image`);
    const checked = await checkPictureUrl(key, url.searchParams, NOW);
    assert.deepEqual(checked, { ok: true, pollId: POLL, side, expires: Date.parse("2026-10-16T12:00:00Z") / 1000 });
  }
});

Deno.test("view: a voter code that voted, and the creator's session, see the counts", async () => {
  const t = fake({
    rpc: {
      poll_view: (args: Record<string, unknown>) => ({
        ok: true,
        expires_at: "2026-10-17T09:00:00Z",
        sizes: {},
        is_creator: args.p_user === USER,
        my_vote: args.p_voter ? "b" : null,
        votes: { a: 1, b: 4 },
      }),
    },
  });
  const voted = await send(t.deps, request("GET", `/polls?id=${POLL}`, { headers: { "X-Poll-Voter": VOTER } }));
  assert.deepEqual([voted.body.my_vote, voted.body.votes], ["b", { a: 1, b: 4 }]);
  const creator = await send(t.deps, request("GET", `/polls?id=${POLL}`, { session: true }));
  assert.equal(creator.body.is_creator, true);
  assert.equal(t.called("poll_view")[1].args.p_user, USER);
  const odd = await send(t.deps, request("GET", `/polls?id=${POLL}`, { headers: { "X-Poll-Voter": "bad code!" } }));
  assert.equal(odd.status, 200);
  assert.equal(t.called("poll_view")[2].args.p_voter, null, "a malformed code is ignored");
});

Deno.test("view: ai says which pictures to label 'Edited with AI'", async () => {
  const view = (ai: unknown) =>
    fake({
      rpc: {
        poll_view: {
          ok: true,
          poll_id: POLL,
          question: null,
          locale: "en",
          created_at: "2026-10-16T09:00:00+00:00",
          expires_at: "2026-10-17T09:00:00+00:00",
          sizes: { a: { width: 540, height: 720 }, b: { width: 720, height: 540 } },
          ai,
          is_creator: false,
          my_vote: null,
          votes: null,
        },
      },
    });
  const labelled = await send(view({ a: false, b: true }).deps, request("GET", `/polls?id=${POLL}`));
  assert.deepEqual(labelled.body.ai, { a: false, b: true });
  const odd = await send(view({ a: "yes", b: 1 }).deps, request("GET", `/polls?id=${POLL}`));
  assert.deepEqual(odd.body.ai, { a: false, b: false }, "only true labels a picture");
});

Deno.test("view: picture URLs never outlive the poll", () => {
  assert.equal(urlExpiry(NOW, new Date("2026-10-16T10:45:30Z")), Date.parse("2026-10-16T10:45:30Z") / 1000);
  assert.equal(
    urlExpiry(new Date("2026-10-16T10:59:59Z"), new Date("2026-10-17T00:00:00Z")),
    Date.parse("2026-10-16T12:00:00Z") / 1000,
  );
});

Deno.test("view: 404 for a poll that isn't live, 400 for a malformed id, 429 passes through", async () => {
  const gone = fake({ rpc: { poll_view: { ok: false, code: "not_found", status: 404 } } });
  let result = await send(gone.deps, request("GET", `/polls?id=${POLL}`));
  assert.deepEqual([result.status, result.body.error.code], [404, "not_found"]);
  for (const path of ["/polls", "/polls?id=short", `/polls?id=${POLL}x`, "/polls?id=Ab3_Xy9-Kq2LmN0!"]) {
    result = await send(gone.deps, request("GET", path));
    assert.equal(result.status, 400, path);
  }
  const busy = fake({ rpc: { poll_view: { ok: false, code: "rate_limited", status: 429, retry_after: 1800 } } });
  result = await send(busy.deps, request("GET", `/polls?id=${POLL}`));
  assert.deepEqual([result.status, result.headers.get("Retry-After")], [429, "1800"]);
});

Deno.test("picture: bytes with a private cache until the URL ends", async () => {
  const t = fake();
  const key = await signingKey(SECRET);
  const expires = urlExpiry(NOW, new Date("2026-10-17T09:00:00Z"));
  const url = new URL(await pictureUrl(key, BASE, POLL, "b", expires));
  const result = await send(t.deps, request("GET", `/polls/image${url.search}`));
  assert.equal(result.status, 200);
  assert.equal(result.headers.get("Content-Type"), "image/jpeg");
  assert.equal(result.headers.get("Cache-Control"), `private, max-age=${expires - NOW.getTime() / 1000}`);
  assert.equal(result.headers.get("Access-Control-Allow-Origin"), "*");
  assert.deepEqual(result.body, Uint8Array.from(atob(base64(makeJpeg(32, 24))), (c) => c.charCodeAt(0)));
  assert.deepEqual(t.called("poll_image")[0].args, { p_poll: POLL, p_side: "b", p_ip: "203.0.113.7" });
});

Deno.test("picture: an expired, changed or malformed URL is refused before the database", async () => {
  const t = fake();
  const key = await signingKey(SECRET);
  const valid = new URL(await pictureUrl(key, BASE, POLL, "a", urlExpiry(NOW, new Date("2026-10-17T09:00:00Z"))));
  const expired = new URL(await pictureUrl(key, BASE, POLL, "a", Math.floor(NOW.getTime() / 1000) - 1));
  const otherSide = new URL(valid);
  otherSide.searchParams.set("side", "b");
  const later = new URL(valid);
  later.searchParams.set("exp", String(Number(valid.searchParams.get("exp")) + 3600));
  const forged = new URL(await pictureUrl(await signingKey("someone else's key"), BASE, POLL, "a", 4102444800));
  for (const [url, status] of [[expired, 403], [otherSide, 403], [later, 403], [forged, 403]] as const) {
    const result = await send(t.deps, request("GET", `/polls/image${url.search}`));
    assert.deepEqual([result.status, result.body.error.code], [status, "url_expired"], url.search);
  }
  for (const search of ["", "?id=x&side=a&exp=1&sig=y", `?id=${POLL}&side=c&exp=4102444800&sig=${"A".repeat(22)}`]) {
    const result = await send(t.deps, request("GET", `/polls/image${search}`));
    assert.equal(result.status, 400, search);
  }
  assert.equal(t.called("poll_image").length, 0);

  const gone = fake({ rpc: { poll_image: { ok: false, code: "not_found", status: 404 } } });
  assert.equal((await send(gone.deps, request("GET", `/polls/image${valid.search}`))).status, 404);
  const capped = fake({ rpc: { poll_image: { ok: false, code: "rate_limited", status: 429 } } });
  assert.equal((await send(capped.deps, request("GET", `/polls/image${valid.search}`))).status, 429);
});

// MARK: - Votes and reports

Deno.test("vote: one choice per voter code; 400 outside the contract; 404 once it ended", async () => {
  const t = fake();
  const result = await send(
    t.deps,
    request("POST", "/polls/vote", { body: { poll_id: POLL, choice: "a", voter: VOTER } }),
  );
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { votes: { a: 2, b: 1 }, my_vote: "a" });
  assert.deepEqual(t.called("cast_poll_vote")[0].args, {
    p_poll: POLL,
    p_voter: VOTER,
    p_choice: "a",
    p_ip: "203.0.113.7",
  });
  for (
    const body of [{ poll_id: POLL, choice: "c", voter: VOTER }, { poll_id: POLL, choice: "a", voter: "short" }, {
      poll_id: "x",
      choice: "a",
      voter: VOTER,
    }, { poll_id: POLL, choice: "a" }]
  ) {
    const refused = await send(t.deps, request("POST", "/polls/vote", { body }));
    assert.equal(refused.status, 400, JSON.stringify(body));
  }
  const ended = fake({ rpc: { cast_poll_vote: { ok: false, code: "not_found", status: 404 } } });
  assert.equal(
    (await send(ended.deps, request("POST", "/polls/vote", { body: { poll_id: POLL, choice: "b", voter: VOTER } })))
      .status,
    404,
  );
  const busy = fake({ rpc: { cast_poll_vote: { ok: false, code: "rate_limited", status: 429, retry_after: 60 } } });
  assert.equal(
    (await send(busy.deps, request("POST", "/polls/vote", { body: { poll_id: POLL, choice: "b", voter: VOTER } })))
      .status,
    429,
  );
});

Deno.test("report: a known reason; says whether the poll came down", async () => {
  const t = fake({ rpc: { report_poll: { ok: true, reported: true, taken_down: true } } });
  const result = await send(t.deps, request("POST", "/polls/report", { body: { poll_id: POLL, reason: "sexual" } }));
  assert.deepEqual([result.status, result.body], [200, { reported: true, taken_down: true }]);
  assert.deepEqual(t.called("report_poll")[0].args, { p_poll: POLL, p_reason: "sexual", p_ip: "203.0.113.7" });
  assert.ok(t.logs.some((entry) => entry.route === "report" && entry.reason === "sexual" && entry.taken_down === true));
  for (const reason of ["minor", "bullying", "privacy", "harmful", "other"]) {
    assert.equal(
      (await send(fake().deps, request("POST", "/polls/report", { body: { poll_id: POLL, reason } }))).status,
      200,
    );
  }
  assert.equal(
    (await send(t.deps, request("POST", "/polls/report", { body: { poll_id: POLL, reason: "ugly" } }))).status,
    400,
  );
  const gone = fake({ rpc: { report_poll: { ok: false, code: "not_found", status: 404 } } });
  assert.equal(
    (await send(gone.deps, request("POST", "/polls/report", { body: { poll_id: POLL, reason: "other" } }))).status,
    404,
  );
});

// MARK: - Her polls

Deno.test("mine: her polls with their links and labels; needs her session", async () => {
  const polls = [
    { poll_id: POLL, question: null, status: "live", ai: { a: true, b: false }, votes: { a: 0, b: 2 } },
    { poll_id: "Zz9_Xy9-Kq2LmN0p", question: "?", status: "taken_down", votes: { a: 1, b: 0 } },
  ];
  const t = fake({
    rpc: { my_polls: { polls, remaining_today: 1, daily_cap: 3 } },
    install: { status: "verified", appTransactionId: "txn-9", environment: "Production" },
  });
  const result = await send(t.deps, request("GET", "/polls/mine", { session: true }));
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    polls: [
      { ...polls[0], share_url: `${SHARE_BASE}${POLL}` },
      { ...polls[1], ai: { a: false, b: false }, share_url: `${SHARE_BASE}Zz9_Xy9-Kq2LmN0p` },
    ],
    remaining_today: 1,
    daily_cap: 3,
  });
  assert.deepEqual(t.called("my_polls")[0].args, {
    p_user: USER,
    p_app_transaction_id: "txn-9",
    p_install_status: "verified",
  });
  assert.equal((await send(fake({ user: null }).deps, request("GET", "/polls/mine"))).status, 401);
});

Deno.test("delete: hers only; 404 otherwise; needs her session", async () => {
  const t = fake();
  const result = await send(t.deps, request("DELETE", `/polls?id=${POLL}`, { session: true }));
  assert.deepEqual([result.status, result.body], [200, { deleted: true }]);
  assert.deepEqual(t.called("delete_poll")[0].args, { p_poll: POLL, p_user: USER });
  const notHers = fake({ rpc: { delete_poll: { deleted: false } } });
  assert.equal((await send(notHers.deps, request("DELETE", `/polls?id=${POLL}`, { session: true }))).status, 404);
  assert.equal((await send(fake({ user: null }).deps, request("DELETE", `/polls?id=${POLL}`))).status, 401);
});

// MARK: - Routing

Deno.test("routing: preflight allows the voter header; other methods and paths are refused", async () => {
  const t = fake();
  const preflight = await handlePolls(request("OPTIONS", "/polls/vote"), t.deps);
  assert.equal(preflight.status, 204);
  assert.ok(preflight.headers.get("Access-Control-Allow-Headers")!.includes("x-poll-voter"));
  assert.ok(preflight.headers.get("Access-Control-Allow-Headers")!.includes("apikey"));
  assert.equal(preflight.headers.get("Access-Control-Max-Age"), "86400");
  assert.equal((await send(t.deps, request("PUT", "/polls"))).status, 405);
  assert.equal((await send(t.deps, request("GET", "/polls/vote"))).status, 405);
  assert.equal((await send(t.deps, request("GET", "/polls/elsewhere"))).status, 404);
  assert.equal(
    (await send(t.deps, request("GET", `/functions/v1/polls?id=${POLL}`))).status,
    200,
    "with the platform's prefix too",
  );
});

Deno.test("locales map as the app sends them", () => {
  assert.equal(normalizeLocale("pt"), "pt-BR");
  assert.equal(normalizeLocale("zh-Hant-TW"), "zh-Hans");
  assert.equal(normalizeLocale("ZH-hans"), "zh-Hans");
  assert.equal(normalizeLocale("tr_TR"), "tr");
  assert.equal(normalizeLocale(undefined), "en");
});

Deno.test("her question reads as she typed it: emoji whole, hidden characters gone", () => {
  assert.equal(cleanQuestion("  Which\n\tone?  👩‍👩‍👧 ❤️  "), "Which one? 👩‍👩‍👧 ❤️");
  assert.equal(cleanQuestion("a‮evil‬ b​c⁦d⁩ ﻿e"), "aevil bcd e");
  assert.equal(cleanQuestion("tag\u{E0041}\u{E0042}s"), "tags");
  assert.equal(cleanQuestion("\u0000\u0007"), "");
  assert.equal(cleanQuestion("é"), "é", "NFC");
});
