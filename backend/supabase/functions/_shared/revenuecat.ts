// RevenueCat customers, server side. The app runs RevenueCat in observer mode
// for subscription analytics, keyed to the Supabase user id, so deleting an
// account must delete those customers too, as the privacy policy promises.
// Deletions are never skipped: DELETE /account queues the user ids first
// (public.pending_revenuecat_deletions) and then works through the queue while
// the key is set; without it they wait there, and the scheduled POST
// /account/revenuecat-deletions retries them, so they all go through as soon
// as the key is added.
// Secrets: REVENUECAT_SECRET_KEY, plus REVENUECAT_PROJECT_ID for a v2 key
// (preferred: limit it to customer_information:customers:read_write). A key
// without a project id is used with the v1 API. v1 and v2 keys are not
// interchangeable.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";

const API = "https://api.revenuecat.com";
const BATCH = 50;

interface Env {
  get(name: string): string | undefined;
}

export interface RevenueCatKey {
  key: string;
  projectID?: string;
}

/** The secret key, or null while it isn't set (deletions then wait in the queue). */
export function revenueCatKey(env: Env = Deno.env): RevenueCatKey | null {
  const key = env.get("REVENUECAT_SECRET_KEY");
  if (!key) return null;
  return { key, projectID: env.get("REVENUECAT_PROJECT_ID") || undefined };
}

/** Customers waiting to be deleted, oldest first. */
export interface DeletionQueue {
  add(userIDs: string[]): Promise<void>;
  next(limit: number): Promise<string[]>;
  /** RevenueCat deleted the customer (or never had it): forget the id. */
  done(userID: string): Promise<void>;
  /** Keep it for the next run, noting what went wrong. */
  failed(userID: string, problem: string): Promise<void>;
}

/** The queue in public.pending_revenuecat_deletions (service role only). */
export function databaseQueue(db: SupabaseClient): DeletionQueue {
  const table = () => db.from("pending_revenuecat_deletions");
  return {
    async add(userIDs) {
      const rows = [...new Set(userIDs.map((id) => id.toLowerCase()))].map((user_id) => ({ user_id }));
      if (rows.length === 0) return;
      const { error } = await table().upsert(rows, { onConflict: "user_id", ignoreDuplicates: true });
      if (error) throw new Error(error.message);
    },
    async next(limit) {
      const { data, error } = await table().select("user_id").order("created_at").limit(limit);
      if (error) throw new Error(error.message);
      return (data ?? []).map((row) => String(row.user_id));
    },
    async done(userID) {
      const { error } = await table().delete().eq("user_id", userID);
      if (error) throw new Error(error.message);
    },
    async failed(userID, problem) {
      const { data } = await table().select("attempts").eq("user_id", userID).maybeSingle();
      const { error } = await table().update({
        attempts: ((data as { attempts?: number } | null)?.attempts ?? 0) + 1,
        last_attempt_at: new Date().toISOString(),
        last_error: problem.slice(0, 300),
      }).eq("user_id", userID);
      if (error) throw new Error(error.message);
    },
  };
}

export interface ProcessOptions {
  /** Defaults to `revenueCatKey()`; null means it isn't set. */
  key?: RevenueCatKey | null;
  fetcher?: typeof fetch;
  limit?: number;
}

export interface ProcessResult {
  deleted: number;
  failed: number;
  /** No key yet: everything stays queued. */
  waiting: boolean;
}

// The app sends `UUID.uuidString`, which is upper case, while Supabase ids are
// lower case. Customer ids are case sensitive, so both spellings are deleted.
function spellings(userID: string): string[] {
  return [...new Set([userID.toUpperCase(), userID.toLowerCase()])];
}

/** Deletes every spelling of one customer. Null when done, otherwise what went wrong. */
async function deleteCustomer(userID: string, key: RevenueCatKey, fetcher: typeof fetch): Promise<string | null> {
  for (const customerID of spellings(userID)) {
    const id = encodeURIComponent(customerID);
    const url = key.projectID
      ? `${API}/v2/projects/${encodeURIComponent(key.projectID)}/customers/${id}`
      : `${API}/v1/subscribers/${id}`;
    try {
      const response = await fetcher(url, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${key.key}` },
        signal: AbortSignal.timeout(8000),
      });
      await response.body?.cancel();
      // 404: never a customer (she never bought), or already deleted.
      if (!response.ok && response.status !== 404) return `HTTP ${response.status}`;
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
  }
  return null;
}

/** Works through the queue while the key is set. Never throws. */
export async function processRevenueCatDeletions(
  queue: DeletionQueue,
  options: ProcessOptions = {},
): Promise<ProcessResult> {
  const key = options.key === undefined ? revenueCatKey() : options.key;
  if (!key) {
    console.warn("REVENUECAT_SECRET_KEY is not set: RevenueCat deletions wait in pending_revenuecat_deletions");
    return { deleted: 0, failed: 0, waiting: true };
  }
  let userIDs: string[];
  try {
    userIDs = await queue.next(options.limit ?? BATCH);
  } catch (error) {
    console.error("couldn't read the RevenueCat deletion queue", error instanceof Error ? error.message : error);
    return { deleted: 0, failed: 0, waiting: false };
  }
  const result: ProcessResult = { deleted: 0, failed: 0, waiting: false };
  for (const userID of userIDs) {
    const problem = await deleteCustomer(userID, key, options.fetcher ?? fetch);
    try {
      if (problem) {
        result.failed += 1;
        console.warn("couldn't delete RevenueCat customer; it stays queued", userID, problem);
        await queue.failed(userID, problem);
      } else {
        result.deleted += 1;
        await queue.done(userID);
      }
    } catch (error) {
      console.error("couldn't update the RevenueCat deletion queue", error instanceof Error ? error.message : error);
    }
  }
  return result;
}

/**
 * For DELETE /account: queues the customers first, so the request survives a
 * missing key or an unreachable RevenueCat, then works through the queue
 * (theirs and any that were waiting). Never throws: deleting the account
 * never waits on RevenueCat.
 */
export async function deleteRevenueCatCustomers(
  queue: DeletionQueue,
  userIDs: string[],
  options: ProcessOptions = {},
): Promise<void> {
  try {
    await queue.add(userIDs);
  } catch (error) {
    console.error("couldn't queue RevenueCat deletions", userIDs, error instanceof Error ? error.message : error);
    // Not queued: at least try them now, as before the queue existed.
    const key = options.key === undefined ? revenueCatKey() : options.key;
    for (const userID of key ? userIDs : []) {
      const problem = await deleteCustomer(userID, key as RevenueCatKey, options.fetcher ?? fetch);
      if (problem) console.error("couldn't delete RevenueCat customer", userID, problem);
    }
    if (!key) console.error("REVENUECAT_SECRET_KEY is not set and the queue failed: delete these customers by hand");
    return;
  }
  await processRevenueCatDeletions(queue, options);
}
