// App Store Server Notifications V2: Apple tells the server about refunds and
// revocations, so a refunded Pro subscription or credit pack stops at once
// instead of at expires_at (see the 20261025 migration).
//
//   POST /app-store-notifications { "signedPayload": "<JWS>" }
//     → 200 { ok, outcome } for every notification Apple signed for this app,
//       whatever its type: Apple retries anything else for days.
//       outcome: "applied", "no_match", "ignored" or "duplicate".
//     → 400 when the payload isn't Apple's, or isn't for this app.
//     → 503 when it can't be checked right now, 500 when it couldn't be
//       recorded: Apple sends it again later.
//
// Apple's servers call it without a JWT (verify_jwt = false in config.toml);
// Apple's signature is the authentication.
import { NotificationTypeV2 } from "npm:@apple/app-store-server-library@3.1.0";
import { CREDIT_PACKS, NotificationRejected, PRO_PRODUCTS, type VerifiedNotification } from "../_shared/apple.ts";
import { json } from "../_shared/http.ts";

/** What a notification does: see record_app_store_notification in the 20261025 migration. */
export type NotificationAction = "revoke" | "restore" | "refund_pack" | "restore_pack" | "none";

interface TransactionFacts {
  productId?: string;
  transactionId?: string;
  originalTransactionId?: string;
}

/**
 * REFUND and REVOKE (Family Sharing) end a Pro subscription, REFUND_REVERSED
 * gives it back; a refunded credit pack is taken back, and a reversed refund
 * returns it. Packs can't be shared with family, so REVOKE never names one.
 * Everything else is only recorded.
 */
export function routeNotification(type: string | undefined, transaction?: TransactionFacts): NotificationAction {
  const product = transaction?.productId ?? "";
  if (PRO_PRODUCTS.has(product) && transaction?.originalTransactionId) {
    if (type === NotificationTypeV2.REFUND || type === NotificationTypeV2.REVOKE) return "revoke";
    if (type === NotificationTypeV2.REFUND_REVERSED) return "restore";
  } else if (Object.hasOwn(CREDIT_PACKS, product) && transaction?.transactionId) {
    if (type === NotificationTypeV2.REFUND) return "refund_pack";
    if (type === NotificationTypeV2.REFUND_REVERSED) return "restore_pack";
  }
  return "none";
}

/** The arguments of public.record_app_store_notification. */
export interface NotificationRecord {
  p_notification_uuid: string;
  p_notification_type: string;
  p_subtype: string | null;
  p_environment: string | null;
  p_action: NotificationAction;
  p_transaction_id: string | null;
  p_original_transaction_id: string | null;
  p_product_id: string | null;
  /** The transaction's expiry: which subscription period a refund covers. */
  p_period_end: string | null;
}

export interface NotificationDeps {
  verify(signedPayload: unknown): Promise<VerifiedNotification>;
  /** Records the notification once and applies its action; returns the outcome. */
  record(row: NotificationRecord): Promise<string>;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function failure(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

export async function handleNotification(req: Request, deps: NotificationDeps): Promise<Response> {
  if (req.method !== "POST") return failure(405, "method_not_allowed", "Method not allowed.");
  let signedPayload: unknown;
  try {
    const body: unknown = JSON.parse(await req.text());
    signedPayload = body && typeof body === "object" ? (body as { signedPayload?: unknown }).signedPayload : undefined;
  } catch {
    signedPayload = undefined;
  }

  let verified: VerifiedNotification;
  try {
    verified = await deps.verify(signedPayload);
  } catch (error) {
    if (error instanceof NotificationRejected && error.retryable) {
      console.error("app store notification not checked; Apple will retry", error.message);
      return failure(503, "unavailable", "Try again later.");
    }
    console.warn("app store notification rejected", error instanceof Error ? error.message : error);
    return failure(400, "invalid_payload", "Not a valid App Store notification.");
  }

  const { notification, transaction } = verified;
  const uuid = notification.notificationUUID;
  const type = notification.notificationType;
  if (!uuid || !UUID_PATTERN.test(uuid) || !type) {
    console.warn("app store notification without a UUID or type");
    return failure(400, "invalid_payload", "Not a valid App Store notification.");
  }

  const action = routeNotification(type, transaction);
  let outcome: string;
  try {
    outcome = await deps.record({
      p_notification_uuid: uuid,
      p_notification_type: type,
      p_subtype: notification.subtype ?? null,
      p_environment: notification.data?.environment ?? null,
      p_action: action,
      p_transaction_id: transaction?.transactionId ?? null,
      p_original_transaction_id: transaction?.originalTransactionId ?? null,
      p_product_id: transaction?.productId ?? null,
      p_period_end: transaction?.expiresDate ? new Date(transaction.expiresDate).toISOString() : null,
    });
  } catch (error) {
    console.error(
      "app store notification not recorded; Apple will retry",
      error instanceof Error ? error.message : error,
    );
    return failure(500, "internal", "Try again later.");
  }
  console.log("app store notification", uuid, type, notification.subtype ?? "-", action, outcome);
  return json({ ok: true, outcome });
}
