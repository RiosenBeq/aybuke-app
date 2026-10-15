// deno test account/
// /account/link and DELETE /account with a stubbed database and Apple: the
// code is exchanged before the merge, `token_stored` tells the truth, a failed
// merge keeps the token, and a Sign in with Apple account is never deleted
// without a token to revoke unless Apple couldn't give the app a code.
// Apple's side is in _shared/apple_signin_test.ts.
import assert from "node:assert/strict";
import type { User } from "npm:@supabase/supabase-js@2.117.3";
import type { AppleCodeExchange } from "../_shared/apple-signin.ts";
import { HttpError } from "../_shared/http.ts";
import { type AccountDeps, link, remove } from "./handler.ts";

const ACCOUNT = "00000000-0000-0000-0000-00000000a001";
const ANONYMOUS = "00000000-0000-0000-0000-00000000b001";

const appleUser = { id: ACCOUNT, is_anonymous: false, identities: [{ provider: "apple" }] } as unknown as User;
const anonymousUser = { id: ANONYMOUS, is_anonymous: true, identities: [] } as unknown as User;

interface Options {
  /** What Apple answers per code; unknown codes are `invalid_grant`. */
  codes?: Record<string, string>;
  stored?: string;
  saveFails?: boolean;
  mergeFails?: boolean;
  configured?: boolean;
}

function fake(options: Options = {}) {
  const log: string[] = [];
  const tokens = new Map<string, string>(options.stored ? [[ACCOUNT, options.stored]] : []);
  const deleted: string[] = [];
  const revoked: string[] = [];
  const queued: string[][] = [];
  const merged: string[] = [];
  const deps: AccountDeps = {
    ownedAnonymousUser: (token) => Promise.resolve(token === "anon-session" ? anonymousUser : null),
    recordMerge: () => Promise.resolve(true),
    mergeAccounts: (from) => {
      log.push("merge");
      if (options.mergeFails) return Promise.resolve(false);
      merged.push(from);
      return Promise.resolve(true);
    },
    mergedIDs: () => Promise.resolve([...merged]),
    deleteUser: (id) => {
      deleted.push(id);
      return Promise.resolve(true);
    },
    queueRevenueCatDeletions: (ids) => {
      queued.push(ids);
      return Promise.resolve();
    },
    storedRefreshToken: (id) => Promise.resolve(tokens.get(id) ?? null),
    saveRefreshToken: (id, token) => {
      if (options.saveFails) return Promise.resolve("42501");
      tokens.set(id, token);
      return Promise.resolve(null);
    },
    exchangeCode: (code): Promise<AppleCodeExchange> => {
      log.push("exchange");
      const token = options.codes?.[code];
      return Promise.resolve(token ? { refreshToken: token } : { refreshToken: null, error: "invalid_grant" });
    },
    revoke: (token) => {
      revoked.push(token);
      return Promise.resolve(true);
    },
    appleConfigured: () => options.configured ?? true,
  };
  return { deps, log, tokens, deleted, revoked, queued };
}

async function quietly<T>(work: () => Promise<T>): Promise<T> {
  const saved = { warn: console.warn, error: console.error };
  console.warn = console.error = () => {};
  try {
    return await work();
  } finally {
    Object.assign(console, saved);
  }
}

async function rejects(work: () => Promise<unknown>, status: number, code: string) {
  await assert.rejects(quietly(work), (error) => {
    assert.ok(error instanceof HttpError);
    assert.equal(error.status, status);
    assert.equal(error.code, code);
    return true;
  });
}

Deno.test("link exchanges the code before merging and stores the token", async () => {
  const f = fake({ codes: { "code-1": "refresh-1" } });
  const response = await link(f.deps, appleUser, { anonymous_token: "anon-session", authorization_code: "code-1" });
  assert.deepEqual(await response.json(), { linked: true, merged: true, token_stored: true });
  assert.deepEqual(f.log, ["exchange", "merge"]);
  assert.equal(f.tokens.get(ACCOUNT), "refresh-1");
  assert.deepEqual(f.deleted, [ANONYMOUS]);
});

Deno.test("link says so when Apple refuses the code or the token can't be saved", async () => {
  const refused = fake();
  const response = await quietly(() => link(refused.deps, appleUser, { authorization_code: "expired" }));
  assert.deepEqual(await response.json(), { linked: true, merged: false, token_stored: false });

  const unsaved = fake({ codes: { "code-1": "refresh-1" }, saveFails: true });
  const second = await quietly(() => link(unsaved.deps, appleUser, { authorization_code: "code-1" }));
  assert.deepEqual(await second.json(), { linked: true, merged: false, token_stored: false });
  assert.equal(unsaved.tokens.size, 0);
});

Deno.test("a failed merge keeps the token, and the retry with the used code still reports it", async () => {
  const f = fake({ codes: { "code-1": "refresh-1" }, mergeFails: true });
  const body = { anonymous_token: "anon-session", authorization_code: "code-1" };
  await rejects(() => link(f.deps, appleUser, body), 500, "merge_failed");
  assert.equal(f.tokens.get(ACCOUNT), "refresh-1");
  assert.deepEqual(f.deleted, [], "the anonymous user stays until its credits moved");

  const retry = fake({ stored: "refresh-1" }); // Apple says invalid_grant to a used code
  const response = await quietly(() => link(retry.deps, appleUser, body));
  assert.deepEqual(await response.json(), { linked: true, merged: true, token_stored: true });
  assert.equal(retry.tokens.get(ACCOUNT), "refresh-1");
});

Deno.test("link is only for Sign in with Apple accounts", async () => {
  await rejects(() => link(fake().deps, anonymousUser, { authorization_code: "code-1" }), 403, "forbidden");
});

Deno.test("deleting revokes the stored token", async () => {
  const f = fake({ stored: "refresh-1" });
  const response = await remove(f.deps, appleUser, {});
  assert.deepEqual(await response.json(), { deleted: true, apple_token_revoked: true });
  assert.deepEqual(f.revoked, ["refresh-1"]);
  assert.deepEqual(f.deleted, [ACCOUNT]);
});

Deno.test("an Apple account without a token asks for Apple first and deletes nothing", async () => {
  const f = fake();
  await rejects(() => remove(f.deps, appleUser, { anonymous_token: "anon-session" }), 409, "apple_reauth_required");
  assert.deepEqual(f.deleted, []);
  assert.deepEqual(f.queued, []);
});

Deno.test("a fresh code on deletion is exchanged and revoked", async () => {
  const f = fake({ codes: { "fresh": "refresh-2" } });
  const response = await remove(f.deps, appleUser, { authorization_code: "fresh" });
  assert.deepEqual(await response.json(), { deleted: true, apple_token_revoked: true });
  assert.deepEqual(f.revoked, ["refresh-2"]);
  assert.deepEqual(f.deleted, [ACCOUNT]);
});

Deno.test("deletion goes ahead when Apple can't help, and says nothing was revoked", async () => {
  const refused = fake();
  const response = await quietly(() => remove(refused.deps, appleUser, { authorization_code: "expired" }));
  assert.deepEqual(await response.json(), { deleted: true, apple_token_revoked: false });
  assert.deepEqual(refused.deleted, [ACCOUNT]);

  const skipped = fake();
  const second = await quietly(() => remove(skipped.deps, appleUser, { skip_apple_revoke: true }));
  assert.deepEqual(await second.json(), { deleted: true, apple_token_revoked: false });

  const unconfigured = fake({ configured: false });
  const third = await quietly(() => remove(unconfigured.deps, appleUser, {}));
  assert.deepEqual(await third.json(), { deleted: true, apple_token_revoked: false });
});

Deno.test("an anonymous user is deleted without Apple, with an unmerged one", async () => {
  const f = fake();
  const owner = { ...anonymousUser, id: ACCOUNT } as User;
  const response = await remove(f.deps, owner, { anonymous_token: "anon-session" });
  assert.deepEqual(await response.json(), { deleted: true, apple_token_revoked: false });
  assert.deepEqual(f.queued, [[ACCOUNT, ANONYMOUS]]);
  assert.deepEqual(f.deleted, [ANONYMOUS, ACCOUNT]);
  assert.deepEqual(f.revoked, []);
});
