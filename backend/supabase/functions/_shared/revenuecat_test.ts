// deno test _shared/
import assert from "node:assert/strict";
import {
  deleteRevenueCatCustomers,
  type DeletionQueue,
  processRevenueCatDeletions,
  revenueCatKey,
} from "./revenuecat.ts";

const ALICE = "0f8fad5b-d9cb-469f-a165-70867728950e";
const BOB = "7c9e6679-7425-40de-944b-e07fc1f90ae7";

/** An in-memory stand-in for public.pending_revenuecat_deletions. */
class MemoryQueue implements DeletionQueue {
  rows = new Map<string, { attempts: number; lastError?: string }>();
  add(userIDs: string[]) {
    for (const id of userIDs) {
      if (!this.rows.has(id.toLowerCase())) this.rows.set(id.toLowerCase(), { attempts: 0 });
    }
    return Promise.resolve();
  }
  next(limit: number) {
    return Promise.resolve([...this.rows.keys()].slice(0, limit));
  }
  done(userID: string) {
    this.rows.delete(userID);
    return Promise.resolve();
  }
  failed(userID: string, problem: string) {
    const row = this.rows.get(userID);
    if (row) this.rows.set(userID, { attempts: row.attempts + 1, lastError: problem });
    return Promise.resolve();
  }
}

/** Answers DELETEs with `status(url)` and records them. */
function revenueCat(status: (url: string) => number | Error) {
  const urls: string[] = [];
  const fetcher = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    urls.push(`${init?.method} ${url}`);
    const answer = status(url);
    return answer instanceof Error ? Promise.reject(answer) : Promise.resolve(new Response(null, { status: answer }));
  }) as typeof fetch;
  return { fetcher, urls };
}

const v1 = { key: "sk_test" };

Deno.test("without the key, deletions wait in the queue instead of being skipped", async () => {
  const queue = new MemoryQueue();
  const api = revenueCat(() => 200);
  await deleteRevenueCatCustomers(queue, [ALICE, BOB.toUpperCase()], { key: null, fetcher: api.fetcher });
  assert.deepEqual([...queue.rows.keys()], [ALICE, BOB]);
  assert.equal(api.urls.length, 0);

  // The next run with the key deletes both spellings of every waiting customer.
  const result = await processRevenueCatDeletions(queue, { key: v1, fetcher: api.fetcher });
  assert.deepEqual(result, { deleted: 2, failed: 0, waiting: false });
  assert.equal(queue.rows.size, 0);
  assert.deepEqual(api.urls, [
    `DELETE https://api.revenuecat.com/v1/subscribers/${ALICE.toUpperCase()}`,
    `DELETE https://api.revenuecat.com/v1/subscribers/${ALICE}`,
    `DELETE https://api.revenuecat.com/v1/subscribers/${BOB.toUpperCase()}`,
    `DELETE https://api.revenuecat.com/v1/subscribers/${BOB}`,
  ]);
});

Deno.test("an account deletion also works through customers that were already waiting", async () => {
  const queue = new MemoryQueue();
  await queue.add([BOB]);
  const api = revenueCat(() => 204);
  await deleteRevenueCatCustomers(queue, [ALICE], { key: v1, fetcher: api.fetcher });
  assert.equal(queue.rows.size, 0);
  assert.equal(api.urls.length, 4);
});

Deno.test("a customer RevenueCat never had counts as deleted", async () => {
  const queue = new MemoryQueue();
  const api = revenueCat(() => 404);
  await deleteRevenueCatCustomers(queue, [ALICE], { key: v1, fetcher: api.fetcher });
  assert.equal(queue.rows.size, 0);
});

Deno.test("failures stay queued for the next run", async () => {
  const queue = new MemoryQueue();
  const down = revenueCat((url) => url.endsWith(ALICE) ? 500 : 200);
  await deleteRevenueCatCustomers(queue, [ALICE, BOB], { key: v1, fetcher: down.fetcher });
  assert.deepEqual([...queue.rows.keys()], [ALICE]);
  assert.deepEqual(queue.rows.get(ALICE), { attempts: 1, lastError: "HTTP 500" });

  const offline = revenueCat(() => new TypeError("error sending request"));
  const result = await processRevenueCatDeletions(queue, { key: v1, fetcher: offline.fetcher });
  assert.deepEqual(result, { deleted: 0, failed: 1, waiting: false });
  assert.equal(queue.rows.get(ALICE)?.attempts, 2);

  const back = revenueCat(() => 200);
  assert.deepEqual(await processRevenueCatDeletions(queue, { key: v1, fetcher: back.fetcher }), {
    deleted: 1,
    failed: 0,
    waiting: false,
  });
  assert.equal(queue.rows.size, 0);
});

Deno.test("a v2 key deletes through the project's customers endpoint", async () => {
  const queue = new MemoryQueue();
  const api = revenueCat(() => 200);
  await deleteRevenueCatCustomers(queue, [ALICE], { key: { key: "sk_v2", projectID: "proj 1" }, fetcher: api.fetcher });
  assert.equal(api.urls[1], `DELETE https://api.revenuecat.com/v2/projects/proj%201/customers/${ALICE}`);
});

Deno.test("a queue that can't be written still tries the deletion directly", async () => {
  const broken: DeletionQueue = {
    add: () => Promise.reject(new Error("relation does not exist")),
    next: () => Promise.reject(new Error("relation does not exist")),
    done: () => Promise.resolve(),
    failed: () => Promise.resolve(),
  };
  const api = revenueCat(() => 200);
  await deleteRevenueCatCustomers(broken, [ALICE], { key: v1, fetcher: api.fetcher });
  assert.equal(api.urls.length, 2);
  // And never throws into the account deletion.
  await deleteRevenueCatCustomers(broken, [ALICE], { key: null, fetcher: api.fetcher });
});

Deno.test("the key comes from the secrets", () => {
  const env = (values: Record<string, string>) => ({ get: (name: string) => values[name] });
  assert.equal(revenueCatKey(env({})), null);
  assert.deepEqual(revenueCatKey(env({ REVENUECAT_SECRET_KEY: "sk" })), { key: "sk", projectID: undefined });
  assert.deepEqual(revenueCatKey(env({ REVENUECAT_SECRET_KEY: "sk", REVENUECAT_PROJECT_ID: "p" })), {
    key: "sk",
    projectID: "p",
  });
});
