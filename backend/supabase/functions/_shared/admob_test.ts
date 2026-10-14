// deno test _shared/
// AdMob server-side verification, against a locally generated P-256 key
// standing in for Google's.
import assert from "node:assert/strict";
import {
  adUnitAllowed,
  base64Decode,
  base64UrlEncode,
  derToRaw,
  isRewardToken,
  rawToDer,
  splitSignedQuery,
  VerificationError,
  VerifierKeys,
  verifyCallback,
} from "./admob.ts";

const TOKEN = "3f9a1c2e-5b7d-4e8f-9a0b-1c2d3e4f5a6b";
const CONTENT = "ad_network=5450213213286189855&ad_unit=1406702504&custom_data=" + TOKEN +
  "&reward_amount=1&reward_item=credit&timestamp=1791972492000&transaction_id=123456789abcdef";

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  return { pair, base64: btoa(String.fromCharCode(...spki)) };
}

async function sign(privateKey: CryptoKey, content: string): Promise<string> {
  const raw = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, new TextEncoder().encode(content)),
  );
  return base64UrlEncode(rawToDer(raw));
}

function keyring(keys: { keyId: number; base64: string }[], now: () => number = () => 0) {
  let fetches = 0;
  const ring = new VerifierKeys(() => {
    fetches++;
    return Promise.resolve({ keys: keys.map((key) => ({ ...key, pem: "unused" })) });
  }, now);
  return { ring, fetches: () => fetches };
}

Deno.test("a callback signed with a published key verifies", async () => {
  const { pair, base64 } = await testKey();
  const { ring } = keyring([{ keyId: 3335741209, base64 }]);
  const query = `${CONTENT}&signature=${await sign(pair.privateKey, CONTENT)}&key_id=3335741209`;
  const callback = await verifyCallback(query, ring);
  assert.equal(callback.transactionId, "123456789abcdef");
  assert.equal(callback.customData, TOKEN);
  assert.equal(callback.adUnit, "1406702504");
  assert.equal(callback.rewardAmount, 1);
  assert.equal(callback.rewardItem, "credit");
  assert.equal(callback.keyId, "3335741209");
  assert.ok(isRewardToken(callback.customData));
});

Deno.test("any change to the signed content fails", async () => {
  const { pair, base64 } = await testKey();
  const { ring } = keyring([{ keyId: 7, base64 }]);
  const signature = await sign(pair.privateKey, CONTENT);
  const tampered = CONTENT.replace("reward_amount=1", "reward_amount=100");
  await assert.rejects(verifyCallback(`${tampered}&signature=${signature}&key_id=7`, ring), VerificationError);
  const reordered = CONTENT.split("&").reverse().join("&");
  await assert.rejects(verifyCallback(`${reordered}&signature=${signature}&key_id=7`, ring), VerificationError);
});

Deno.test("another key's signature fails", async () => {
  const google = await testKey();
  const attacker = await testKey();
  const { ring } = keyring([{ keyId: 7, base64: google.base64 }]);
  const query = `${CONTENT}&signature=${await sign(attacker.pair.privateKey, CONTENT)}&key_id=7`;
  await assert.rejects(verifyCallback(query, ring), VerificationError);
});

Deno.test("an unknown key id refetches the keys once, then fails closed", async () => {
  const { pair, base64 } = await testKey();
  let clock = 0;
  const { ring, fetches } = keyring([{ keyId: 7, base64 }], () => clock);
  const signature = await sign(pair.privateKey, CONTENT);
  await verifyCallback(`${CONTENT}&signature=${signature}&key_id=7`, ring);
  assert.equal(fetches(), 1);
  await verifyCallback(`${CONTENT}&signature=${signature}&key_id=7`, ring);
  assert.equal(fetches(), 1, "cached");

  clock = 2 * 60 * 1000;
  await assert.rejects(verifyCallback(`${CONTENT}&signature=${signature}&key_id=8`, ring), VerificationError);
  assert.equal(fetches(), 2, "an unknown key id fetches the keys again");
  await assert.rejects(verifyCallback(`${CONTENT}&signature=${signature}&key_id=8`, ring), VerificationError);
  assert.equal(fetches(), 2, "but not on every callback");

  clock = 13 * 60 * 60 * 1000;
  await verifyCallback(`${CONTENT}&signature=${signature}&key_id=7`, ring);
  assert.equal(fetches(), 3, "keys are never older than the cache limit");
});

Deno.test("keys that can't be fetched fail closed", async () => {
  const { pair } = await testKey();
  const ring = new VerifierKeys(() => Promise.reject(new Error("offline")));
  const query = `${CONTENT}&signature=${await sign(pair.privateKey, CONTENT)}&key_id=7`;
  await assert.rejects(verifyCallback(query, ring));
});

Deno.test("a signature over the percent-decoded query verifies too", async () => {
  const { pair, base64 } = await testKey();
  const { ring } = keyring([{ keyId: 7, base64 }]);
  const encoded = CONTENT.replace("reward_item=credit", "reward_item=bonus%20credit");
  const signature = await sign(pair.privateKey, decodeURIComponent(encoded));
  const callback = await verifyCallback(`${encoded}&signature=${signature}&key_id=7`, ring);
  assert.equal(callback.rewardItem, "bonus credit");
});

Deno.test("malformed callbacks are rejected before any crypto", () => {
  assert.throws(() => splitSignedQuery(CONTENT), VerificationError);
  assert.throws(() => splitSignedQuery(`${CONTENT}&signature=abc`), VerificationError);
  assert.throws(() => splitSignedQuery(`${CONTENT}&signature=abc&key_id=x`), VerificationError);
  assert.throws(() => splitSignedQuery(`${CONTENT}&signature=abc&key_id=7&extra=1`), VerificationError);
  assert.throws(() => splitSignedQuery(`signature=abc&key_id=7`), VerificationError);
  const { content, signature, keyId } = splitSignedQuery(`${CONTENT}&signature=abc&key_id=7`);
  assert.equal(content, CONTENT);
  assert.equal(signature, "abc");
  assert.equal(keyId, "7");
});

Deno.test("DER signatures convert to the raw form and back", () => {
  const raw = new Uint8Array(64);
  raw[0] = 0x80; // r needs a leading zero in DER
  raw[63] = 0x01; // s is short
  const der = rawToDer(raw);
  assert.equal(der[0], 0x30);
  assert.deepEqual(derToRaw(der), raw);
  assert.throws(() => derToRaw(new Uint8Array([0x31, 0x00])));
  assert.throws(() => derToRaw(der.subarray(0, der.length - 1)));
  assert.throws(() => derToRaw(new Uint8Array([...der, 0x00])));
  assert.deepEqual(base64Decode(base64UrlEncode(der)), der);
});

Deno.test("only our rewarded ad units are accepted", () => {
  const ours = "ca-app-pub-2292230772061554/1406702504";
  assert.ok(adUnitAllowed("1406702504", ours));
  assert.ok(adUnitAllowed("1406702504", `ca-app-pub-1/1, ${ours}`));
  assert.ok(adUnitAllowed("1406702504", "1406702504"));
  assert.ok(!adUnitAllowed("1712485313", ours), "Google's test unit isn't ours");
  assert.ok(!adUnitAllowed("1406702504", ""), "an empty allow-list allows nothing");
  assert.ok(!adUnitAllowed("1406702504", undefined));
  assert.ok(!adUnitAllowed("", ours));
});

Deno.test("reward tokens are UUIDs", () => {
  assert.ok(isRewardToken(TOKEN));
  assert.ok(!isRewardToken("00000000-0000-0000-0000-0000000000b1'; drop table"));
  assert.ok(!isRewardToken(""));
});
