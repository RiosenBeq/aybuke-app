// What /account/link and DELETE /account do, with the database and Apple
// behind `AccountDeps` so handler_test.ts can run them without either.
import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2.117.3";
import {
  type AppleCodeExchange,
  appleSignInConfigured,
  exchangeAuthorizationCode,
  revokeRefreshToken,
} from "../_shared/apple-signin.ts";
import { HttpError, json } from "../_shared/http.ts";
import { databaseQueue, deleteRevenueCatCustomers } from "../_shared/revenuecat.ts";

export interface LinkRequest {
  anonymous_token?: string;
  authorization_code?: string;
}

export interface DeleteRequest {
  anonymous_token?: string;
  /** A fresh Sign in with Apple code, sent when the server holds no token to revoke. */
  authorization_code?: string;
  /** Apple couldn't give the app a code (not a cancel): delete anyway, without revoking. */
  skip_apple_revoke?: boolean;
}

export interface AccountDeps {
  /** The anonymous user behind `token`, if the caller holds its session and it isn't `owner`. */
  ownedAnonymousUser(token: unknown, owner: User): Promise<User | null>;
  recordMerge(accountID: string, anonymousID: string): Promise<boolean>;
  mergeAccounts(from: string, to: string): Promise<boolean>;
  mergedIDs(accountID: string): Promise<string[]>;
  deleteUser(id: string): Promise<boolean>;
  queueRevenueCatDeletions(ids: string[]): Promise<void>;
  storedRefreshToken(userID: string): Promise<string | null>;
  /** Null when saved, else the database error code (never the token). */
  saveRefreshToken(userID: string, token: string): Promise<string | null>;
  exchangeCode(code: string): Promise<AppleCodeExchange>;
  revoke(token: string): Promise<boolean>;
  appleConfigured(): boolean;
}

export function isAppleAccount(user: User): boolean {
  return !user.is_anonymous && (user.identities ?? []).some((identity) => identity.provider === "apple");
}

function code(value: unknown): string | null {
  return typeof value === "string" && value ? value : null;
}

/**
 * Right after Sign in with Apple. The code is exchanged first: it lasts five
 * minutes and works once, so a failed merge mustn't cost the refresh token.
 * `token_stored` says whether the account now has a token that deleting it can
 * revoke (a retry with a used code keeps the one saved the first time).
 */
export async function link(deps: AccountDeps, user: User, body: LinkRequest): Promise<Response> {
  if (!isAppleAccount(user)) throw new HttpError(403, "forbidden", "Sign in with Apple first.");

  const authorizationCode = code(body.authorization_code);
  let tokenStored = false;
  if (authorizationCode) {
    const exchange = await deps.exchangeCode(authorizationCode).catch((error): AppleCodeExchange => {
      console.error("apple code exchange failed", error instanceof Error ? error.name : "");
      return { refreshToken: null, error: "exception" };
    });
    if (exchange.refreshToken) {
      const saveError = await deps.saveRefreshToken(user.id, exchange.refreshToken);
      if (saveError) console.error("couldn't save the Apple refresh token for", user.id, saveError);
      tokenStored = saveError === null;
    } else {
      console.warn("apple code exchange gave no token for", user.id, exchange.error);
    }
  }
  if (!tokenStored) {
    tokenStored = (await deps.storedRefreshToken(user.id).catch(() => null)) !== null;
    if (!tokenStored) console.warn("no Apple refresh token stored for", user.id, "so deleting it will ask Apple again");
  }

  let merged = false;
  const previous = await deps.ownedAnonymousUser(body.anonymous_token, user);
  if (previous) {
    // Recorded first: RevenueCat keeps purchases made while anonymous on that
    // customer, so deleting the account must find it.
    if (!await deps.recordMerge(user.id, previous.id) || !await deps.mergeAccounts(previous.id, user.id)) {
      throw new HttpError(500, "merge_failed", "Couldn't move your credits. Please try again.");
    }
    if (!await deps.deleteUser(previous.id)) console.warn("couldn't delete merged anonymous user", previous.id);
    merged = true;
  }
  return json({ linked: true, merged, token_stored: tokenStored });
}

/**
 * Deletes the account. A Sign in with Apple account without a stored token is
 * answered 409 `apple_reauth_required` before anything is deleted: the app
 * asks Apple for a fresh code and sends it, so the token can still be revoked.
 */
export async function remove(deps: AccountDeps, user: User, body: DeleteRequest): Promise<Response> {
  const apple = isAppleAccount(user);
  const stored = await deps.storedRefreshToken(user.id);
  const authorizationCode = code(body.authorization_code);
  if (apple && !stored && !authorizationCode && body.skip_apple_revoke !== true && deps.appleConfigured()) {
    throw new HttpError(409, "apple_reauth_required", "Confirm with Apple to delete your account.");
  }

  const unmerged = await deps.ownedAnonymousUser(body.anonymous_token, user);
  // Queued before the user is deleted, so a failed deletion can be retried and
  // still find the merged ids; without the key they wait in the queue. Never
  // fails the deletion.
  await deps.queueRevenueCatDeletions([user.id, ...await deps.mergedIDs(user.id), ...(unmerged ? [unmerged.id] : [])]);
  if (unmerged && !await deps.deleteUser(unmerged.id)) {
    throw new HttpError(500, "internal", "Couldn't delete your account. Please contact support.");
  }

  const tokens = stored ? [stored] : [];
  if (authorizationCode) {
    const exchange = await deps.exchangeCode(authorizationCode).catch((): AppleCodeExchange => ({
      refreshToken: null,
      error: "exception",
    }));
    if (exchange.refreshToken && exchange.refreshToken !== stored) tokens.push(exchange.refreshToken);
    if (!exchange.refreshToken) console.error("apple code exchange on deletion failed for", user.id, exchange.error);
  }
  let revoked = false;
  for (const token of tokens) {
    const ok = await deps.revoke(token).catch((error) => {
      console.error("apple token revocation failed", error instanceof Error ? error.name : "");
      return false;
    });
    revoked ||= ok;
  }
  if (apple && !revoked) {
    console.error(
      "Sign in with Apple token NOT revoked for deleted account",
      user.id,
      deps.appleConfigured() ? "" : "(APPLE_TEAM_ID / APPLE_SIGNIN_KEY_ID / APPLE_SIGNIN_PRIVATE_KEY not set)",
      body.skip_apple_revoke === true ? "(the app couldn't get a code from Apple)" : "",
    );
  }
  if (!await deps.deleteUser(user.id)) {
    throw new HttpError(500, "internal", "Couldn't delete your account. Please contact support.");
  }
  return json({ deleted: true, apple_token_revoked: revoked });
}

/** The real database and Apple. */
export function accountDeps(db: SupabaseClient): AccountDeps {
  return {
    // Holding an anonymous user's session proves the caller owns it.
    async ownedAnonymousUser(token, owner) {
      if (typeof token !== "string" || !token) return null;
      const { data } = await db.auth.getUser(token);
      const previous = data.user;
      return previous?.is_anonymous && previous.id !== owner.id ? previous : null;
    },
    async recordMerge(accountID, anonymousID) {
      const { error } = await db.from("merged_users").upsert({ account_id: accountID, anonymous_id: anonymousID });
      if (error) console.error("couldn't record the merge", error.code);
      return !error;
    },
    async mergeAccounts(from, to) {
      const { error } = await db.rpc("merge_accounts", { p_from: from, p_to: to });
      if (error) console.error("merge_accounts failed", error.code);
      return !error;
    },
    async mergedIDs(accountID) {
      const { data } = await db.from("merged_users").select("anonymous_id").eq("account_id", accountID);
      return (data ?? []).map((row) => String(row.anonymous_id));
    },
    async deleteUser(id) {
      const { error } = await db.auth.admin.deleteUser(id);
      return !error;
    },
    queueRevenueCatDeletions: (ids) => deleteRevenueCatCustomers(databaseQueue(db), ids),
    async storedRefreshToken(userID) {
      const { data, error } = await db.from("apple_accounts").select("refresh_token").eq("user_id", userID)
        .maybeSingle();
      if (error) console.error("couldn't read the Apple refresh token", error.code);
      return typeof data?.refresh_token === "string" && data.refresh_token ? data.refresh_token : null;
    },
    async saveRefreshToken(userID, token) {
      const { error } = await db.from("apple_accounts").upsert({
        user_id: userID,
        refresh_token: token,
        updated_at: new Date().toISOString(),
      });
      return error ? (error.code || "unknown") : null;
    },
    exchangeCode: exchangeAuthorizationCode,
    revoke: revokeRefreshToken,
    appleConfigured: appleSignInConfigured,
  };
}
