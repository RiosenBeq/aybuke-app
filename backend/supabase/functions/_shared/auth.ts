import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2.117.3";
import { HttpError, requireEnv } from "./http.ts";

/** Service-role client: bypasses RLS, so only ever use it server-side. */
export function serviceClient(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/**
 * For scheduled maintenance calls (pg_cron + pg_net): the bearer token must be
 * the service role key itself. Compared in constant time.
 */
export function requireServiceRole(req: Request): void {
  const token = new TextEncoder().encode(req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "");
  const expected = new TextEncoder().encode(requireEnv("SUPABASE_SERVICE_ROLE_KEY"));
  let difference = token.length ^ expected.length;
  for (let i = 0; i < expected.length; i++) difference |= (token[i] ?? 0) ^ expected[i];
  if (difference !== 0) throw new HttpError(403, "forbidden", "Not allowed.");
}

/** Resolves the (anonymous) user from the `Authorization: Bearer <jwt>` header. */
export async function requireUser(db: SupabaseClient, req: Request): Promise<User> {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  if (!token) throw new HttpError(401, "unauthorized", "Missing session.");
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "unauthorized", "Your session expired. Please try again.");
  return data.user;
}
