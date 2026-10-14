// Sign in with Apple, server side. The app signs in with Supabase's native
// Apple provider (ID token); this module only handles what Apple asks of apps
// that offer account deletion: exchange the one-time authorization code for a
// refresh token, and revoke that token when the account is deleted.
// Secrets: APPLE_TEAM_ID, APPLE_SIGNIN_KEY_ID and APPLE_SIGNIN_PRIVATE_KEY (the
// .p8 key's contents). The client id is the app's bundle id (APPLE_BUNDLE_ID).

const APPLE_ID_URL = "https://appleid.apple.com";

interface AppleSignInConfig {
  teamId: string;
  keyId: string;
  privateKey: string;
  clientId: string;
}

/** False while the Sign in with Apple key secrets are missing: tokens can be neither kept nor revoked. */
export function appleSignInConfigured(): boolean {
  return appleConfig() !== null;
}

function appleConfig(): AppleSignInConfig | null {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_SIGNIN_KEY_ID");
  const privateKey = Deno.env.get("APPLE_SIGNIN_PRIVATE_KEY");
  if (!teamId || !keyId || !privateKey) {
    console.warn(
      "APPLE_TEAM_ID, APPLE_SIGNIN_KEY_ID or APPLE_SIGNIN_PRIVATE_KEY is not set: Sign in with Apple tokens can't be kept or revoked",
    );
    return null;
  }
  return {
    teamId,
    keyId,
    privateKey: privateKey.replace(/\\n/g, "\n"),
    clientId: Deno.env.get("APPLE_BUNDLE_ID") ?? "app.glowlit.ios",
  };
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Return type inferred on purpose: newer TypeScript wants Uint8Array<ArrayBuffer> for Web Crypto.
function pkcs8(pem: string) {
  const base64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

/** The ES256 client secret Apple expects: a short-lived JWT signed with the .p8 key. */
async function clientSecret(config: AppleSignInConfig): Promise<string> {
  const encoder = new TextEncoder();
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: config.teamId, iat: now, exp: now + 300, aud: APPLE_ID_URL, sub: config.clientId };
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = base64url(encoder.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

/** Exchanges the app's authorization code for Apple's refresh token. Null when not configured or rejected. */
export async function exchangeAuthorizationCode(code: string): Promise<string | null> {
  const config = appleConfig();
  if (!config) return null;
  const response = await fetch(`${APPLE_ID_URL}/auth/token`, {
    method: "POST",
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: await clientSecret(config),
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) {
    console.warn("apple code exchange failed", response.status);
    return null;
  }
  const data = await response.json() as { refresh_token?: string };
  return data.refresh_token ?? null;
}

/** Revokes a refresh token so the app disappears from the user's Apple ID settings. Best effort. */
export async function revokeRefreshToken(token: string): Promise<boolean> {
  const config = appleConfig();
  if (!config) return false;
  const response = await fetch(`${APPLE_ID_URL}/auth/revoke`, {
    method: "POST",
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: await clientSecret(config),
      token,
      token_type_hint: "refresh_token",
    }),
  });
  if (!response.ok) console.warn("apple token revocation failed", response.status);
  return response.ok;
}
