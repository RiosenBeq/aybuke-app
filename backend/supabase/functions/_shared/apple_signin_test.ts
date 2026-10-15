// deno test _shared/
// Sign in with Apple, server side: the client secret JWT verifies with the
// key's public half and carries the claims Apple expects, both Apple calls send
// the right form fields, and Apple's error codes come back without secrets.
import assert from "node:assert/strict";
import { appleSignInConfigured, exchangeAuthorizationCode, revokeRefreshToken } from "./apple-signin.ts";

// Return type inferred: Web Crypto wants Uint8Array<ArrayBuffer>.
function b64urlDecode(s: string) {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

interface Call {
  url: string;
  form: URLSearchParams;
  contentType: string | null;
}

/** Runs `body` with these secrets and a stubbed Apple, then puts both back. */
async function withApple(
  env: Record<string, string>,
  answer: (url: string) => Response | Promise<Response>,
  body: (calls: Call[]) => Promise<void>,
) {
  const realGet = Deno.env.get;
  const realFetch = globalThis.fetch;
  const realLog = { warn: console.warn, error: console.error };
  const calls: Call[] = [];
  Deno.env.get = (name: string) => env[name];
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const req = new Request(input, init);
    calls.push({
      url: req.url,
      form: new URLSearchParams(await req.text()),
      contentType: req.headers.get("content-type"),
    });
    return answer(req.url);
  }) as typeof fetch;
  console.warn = console.error = () => {};
  try {
    await body(calls);
  } finally {
    Deno.env.get = realGet;
    globalThis.fetch = realFetch;
    Object.assign(console, realLog);
  }
}

async function secrets() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const b64 = btoa(String.fromCharCode(...pkcs8));
  // Like a .p8 pasted into a secret with literal "\n" escapes.
  const pem = "-----BEGIN PRIVATE KEY-----\\n" + b64.match(/.{1,64}/g)!.join("\\n") + "\\n-----END PRIVATE KEY-----";
  return {
    publicKey: pair.publicKey,
    env: {
      APPLE_TEAM_ID: "TEAM123456",
      APPLE_SIGNIN_KEY_ID: "KEY1234567",
      APPLE_SIGNIN_PRIVATE_KEY: pem,
      APPLE_BUNDLE_ID: "app.glowlit.ios",
    },
  };
}

Deno.test("without the key secrets nothing is sent", async () => {
  await withApple({}, () => new Response("", { status: 500 }), async (calls) => {
    assert.equal(appleSignInConfigured(), false);
    assert.deepEqual(await exchangeAuthorizationCode("c"), { refreshToken: null, error: "not_configured" });
    assert.equal(await revokeRefreshToken("t"), false);
    assert.equal(calls.length, 0);
  });
});

Deno.test("the client secret, the token exchange and the revocation", async () => {
  const { publicKey, env } = await secrets();
  const answer = (url: string) =>
    url.endsWith("/auth/token")
      ? new Response(JSON.stringify({ refresh_token: "r.token", access_token: "a", id_token: "i" }))
      : new Response("");
  await withApple(env, answer, async (calls) => {
    assert.equal(appleSignInConfigured(), true);
    assert.deepEqual(await exchangeAuthorizationCode("auth-code"), { refreshToken: "r.token" });
    assert.equal(await revokeRefreshToken("r.token"), true);

    const [token, revoke] = calls;
    assert.equal(token.url, "https://appleid.apple.com/auth/token");
    assert.ok(token.contentType?.startsWith("application/x-www-form-urlencoded"));
    assert.equal(token.form.get("grant_type"), "authorization_code");
    assert.equal(token.form.get("code"), "auth-code");
    assert.equal(token.form.get("client_id"), "app.glowlit.ios");
    assert.equal(revoke.url, "https://appleid.apple.com/auth/revoke");
    assert.equal(revoke.form.get("token_type_hint"), "refresh_token");
    assert.equal(revoke.form.get("token"), "r.token");

    for (const call of calls) {
      const [h, p, s] = call.form.get("client_secret")!.split(".");
      const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
      const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
      assert.deepEqual(header, { alg: "ES256", kid: "KEY1234567" });
      assert.equal(payload.iss, "TEAM123456");
      assert.equal(payload.sub, "app.glowlit.ios");
      assert.equal(payload.aud, "https://appleid.apple.com");
      assert.equal(payload.exp - payload.iat, 300);
      assert.ok(Math.abs(payload.iat - Date.now() / 1000) < 5);
      const signature = b64urlDecode(s);
      assert.equal(signature.length, 64, "raw r||s (JWS), not DER");
      const verified = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        publicKey,
        signature,
        new TextEncoder().encode(`${h}.${p}`),
      );
      assert.ok(verified, "signed with the key");
    }
  });
});

Deno.test("Apple's refusals come back as its error code, nothing more", async () => {
  const { env } = await secrets();
  const cases: [Response | Error, string][] = [
    [new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 }), "invalid_grant"],
    [new Response(JSON.stringify({ error: "invalid_client" }), { status: 400 }), "invalid_client"],
    [new Response(JSON.stringify({ error: "<b>not a code</b>" }), { status: 400 }), "http_400"],
    [new Response("Service Unavailable", { status: 503 }), "http_503"],
    [new Response(JSON.stringify({ access_token: "a" })), "no_refresh_token"],
    [new TypeError("dns"), "network"],
  ];
  for (const [reply, error] of cases) {
    await withApple(env, () => {
      if (reply instanceof Error) throw reply;
      return reply.clone();
    }, async () => {
      assert.deepEqual(await exchangeAuthorizationCode("used-code"), { refreshToken: null, error });
    });
  }
  await withApple(env, () => new Response(JSON.stringify({ error: "invalid_request" }), { status: 400 }), async () => {
    assert.equal(await revokeRefreshToken("t"), false);
  });
});
