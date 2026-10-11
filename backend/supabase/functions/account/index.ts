// In-app account deletion (App Store Review Guideline 5.1.1(v)).
//   DELETE /account → deletes the user; wallets, ledger, jobs and entitlements cascade.
// Apple subscriptions are billed by Apple and must be cancelled by the user there.
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (req.method !== "DELETE") throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    const db = serviceClient();
    const user = await requireUser(db, req);
    const { error } = await db.auth.admin.deleteUser(user.id);
    if (error) throw new HttpError(500, "internal", "Couldn't delete your account. Please contact support.");
    return json({ deleted: true });
  } catch (error) {
    return errorResponse(error);
  }
});
