// Grants a consumable credit pack after verifying Apple's signed transaction.
//   POST /credits-redeem { "signed_transaction": "<JWS>" } → { credits_remaining }
// Idempotent per Apple transaction id, so StoreKit redeliveries are safe.
import { CREDIT_PACKS, verifyTransaction } from "../_shared/apple.ts";
import { requireUser, serviceClient } from "../_shared/auth.ts";
import { corsHeaders, errorResponse, HttpError, json } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Method not allowed.");
    const db = serviceClient();
    const user = await requireUser(db, req);
    const body = await req.json().catch(() => ({})) as { signed_transaction?: string };
    if (!body.signed_transaction) throw new HttpError(400, "bad_request", "Missing signed_transaction.");

    const transaction = await verifyTransaction(body.signed_transaction).catch(() => {
      throw new HttpError(400, "invalid_transaction", "We couldn't verify this purchase.");
    });
    const credits = transaction.productId ? CREDIT_PACKS[transaction.productId] : undefined;
    if (!credits || !transaction.transactionId) {
      throw new HttpError(400, "invalid_transaction", "This isn't a credit pack.");
    }
    if (transaction.revocationDate) throw new HttpError(409, "refunded", "This purchase was refunded.");

    const { data, error } = await db.rpc("grant_pack", {
      p_user: user.id,
      p_credits: credits,
      p_transaction_id: transaction.transactionId,
    });
    if (error) throw new HttpError(500, "internal", "Couldn't add your credits. We'll retry.");
    return json({ credits_remaining: data });
  } catch (error) {
    return errorResponse(error);
  }
});
