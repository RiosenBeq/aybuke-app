// App Store Server Notifications V2 (refunds and revocations): see handler.ts.
// Deploy with: supabase functions deploy app-store-notifications --no-verify-jwt
// App Store Connect › App Information › App Store Server Notifications:
// Version 2, the same URL for Production and Sandbox.
import { verifyNotification } from "../_shared/apple.ts";
import { serviceClient } from "../_shared/auth.ts";
import { handleNotification } from "./handler.ts";

Deno.serve((req) =>
  handleNotification(req, {
    verify: (signedPayload) => verifyNotification(signedPayload),
    record: async (row) => {
      const { data, error } = await serviceClient().rpc("record_app_store_notification", row);
      if (error) throw new Error(error.message);
      return String(data);
    },
  })
);
