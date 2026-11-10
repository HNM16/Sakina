#!/usr/bin/env node
/**
 * Does a closed app actually get notified?
 *
 * Push is the one delivery path that cannot be tested through the socket,
 * because its entire reason for existing is that the socket is gone. So this
 * drives the real thing: real gateway, real Redis presence, real queue, real
 * worker — with the push provider swapped for one that records instead of
 * calling Google and Apple.
 *
 * The questions that matter:
 *   - does an offline device get a push?
 *   - does an ONLINE device get left alone? (a notification for a message
 *     already on screen is the fastest way to make people mute an app)
 *   - does the sender get pushed for their own message? (it must not)
 *   - is message text kept out of the payload?
 *   - is a dead token retired instead of retried forever?
 *
 *   node services/worker/scripts/push-smoke.mjs
 *
 * Needs api :4000, gateway :4001, worker :4003 with PUSH_PROVIDER=console.
 */
import WebSocket from "ws";
import { randomUUID } from "node:crypto";

const API = process.env.API_URL ?? "http://127.0.0.1:4000";
const WS_URL = process.env.WS_URL ?? "ws://127.0.0.1:4001/ws";
const WORKER = process.env.WORKER_URL ?? "http://127.0.0.1:4003";

let failures = 0;
function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

async function api(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    ...options,
    headers: { "content-type": "application/json", ...(options.headers ?? {}) },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path} -> ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

async function register(email, pushToken) {
  const deviceId = randomUUID();
  const identity = { kind: "email", value: email };

  const { dev_code } = await api("/v1/auth/otp/request", {
    method: "POST",
    body: JSON.stringify({ identity, locale: "tg" }),
  });

  const { user, tokens } = await api("/v1/auth/otp/verify", {
    method: "POST",
    body: JSON.stringify({
      identity,
      code: dev_code,
      device: { device_id: deviceId, platform: "android", name: "Test handset" },
    }),
  });

  if (pushToken) {
    await api("/v1/devices/push-token", {
      method: "POST",
      headers: { authorization: `Bearer ${tokens.access_token}` },
      body: JSON.stringify({ device_id: deviceId, token: pushToken, provider: "fcm" }),
    });
  }

  return { user, tokens, deviceId, pushToken };
}

function connect(session) {
  const socket = new WebSocket(WS_URL);
  return new Promise((resolve, reject) => {
    socket.on("error", reject);
    socket.on("message", (raw) => {
      const frame = JSON.parse(raw.toString());
      if (frame.t === "ready") resolve({ socket, send: (f) => socket.send(JSON.stringify(f)) });
    });
    socket.on("open", () => {
      socket.send(
        JSON.stringify({
          t: "hello",
          d: { v: 1, token: session.tokens.access_token, device_id: session.deviceId },
        }),
      );
    });
  });
}

const pushes = async () => (await (await fetch(`${WORKER}/dev/pushes`)).json()).pushes;
const forToken = (list, token) => list.filter((p) => p.token === token);
const settle = (ms = 1200) => new Promise((r) => setTimeout(r, ms));

const stamp = Date.now().toString().slice(-8);

console.log("\nSakina push smoke test\n");

const health = await (await fetch(`${WORKER}/health`)).json();
check("worker is up", health.ok === true, `provider=${health.push_provider}`);
if (health.push_provider !== "console") {
  console.log("\n  ! needs PUSH_PROVIDER=console to inspect what was sent\n");
  process.exit(1);
}

// --- setup ----------------------------------------------------------------
console.log("\nsetup");

const aliceToken = `fcm-alice-${stamp}`;
const bobToken = `fcm-bob-${stamp}`;

const alice = await register(`alice${stamp}@example.com`, aliceToken);
const bob = await register(`bob${stamp}@example.com`, bobToken);
check("two users with push tokens registered", !!alice.user.id && !!bob.user.id);

const me = await api("/v1/me", {
  headers: { authorization: `Bearer ${bob.tokens.access_token}` },
});
check("the token is attached to the device", me.devices.length === 1);

const chat = await api("/v1/chats", {
  method: "POST",
  headers: { authorization: `Bearer ${alice.tokens.access_token}` },
  body: JSON.stringify({ kind: "direct", peer_id: bob.user.id }),
});
check("chat created", chat.kind === "direct");

// --- the core case: recipient is offline ----------------------------------
console.log("\nrecipient offline (the whole point)");

const aliceWs = await connect(alice);
// Bob never connects — his app is closed, exactly like a phone in a pocket.

const before = (await pushes()).length;
aliceWs.send({
  t: "send",
  d: {
    client_id: randomUUID(),
    chat_id: chat.id,
    payload: { type: "text", text: "Салом! Ту дар куҷо?" },
  },
});
await settle();

const afterOffline = await pushes();
const bobPushes = forToken(afterOffline, bobToken);
check("the offline recipient got a push", bobPushes.length === 1, `${bobPushes.length} push(es)`);
check(
  "the sender did NOT get a push for their own message",
  forToken(afterOffline, aliceToken).length === 0,
);
check("exactly one push was sent in total", afterOffline.length - before === 1);

// --- the payload ----------------------------------------------------------
console.log("\npayload");

const push = bobPushes[0];
check("it carries the chat id", push?.data?.chat_id === chat.id);
check("it carries the seq so the client can sync", push?.data?.seq === "1");
check(
  "it does NOT carry the message text",
  !JSON.stringify(push).includes("Ту дар куҷо"),
  "content stays out of Google and Apple's hands",
);
check("the body is generic", push?.body === "Паёми нав", push?.body);
check("it collapses per chat", push?.collapseKey === chat.id);

// --- the other core case: recipient is online -----------------------------
console.log("\nrecipient online");

const bobWs = await connect(bob);
await settle(400);

const beforeOnline = (await pushes()).length;
aliceWs.send({
  t: "send",
  d: { client_id: randomUUID(), chat_id: chat.id, payload: { type: "text", text: "Паёми дуюм" } },
});
await settle();

const afterOnline = await pushes();
check(
  "an online device is NOT pushed — it already has the message",
  afterOnline.length === beforeOnline,
  `${afterOnline.length - beforeOnline} unwanted push(es)`,
);

// --- and back offline again -----------------------------------------------
console.log("\nrecipient goes offline again");

bobWs.socket.close();
// Presence is cleared on disconnect, so the next message should push again.
await settle(600);

aliceWs.send({
  t: "send",
  d: { client_id: randomUUID(), chat_id: chat.id, payload: { type: "text", text: "Паёми сеюм" } },
});
await settle();

check(
  "pushes resume once the app closes",
  forToken(await pushes(), bobToken).length === 2,
  `${forToken(await pushes(), bobToken).length} total for Bob`,
);

// --- dead tokens ----------------------------------------------------------
console.log("\ndead tokens");

// The console provider treats a "dead-" prefix as unregistered, so the
// retirement path is exercised rather than discovered in production.
const ghost = await register(`ghost${stamp}@example.com`, `dead-${stamp}`);
const ghostChat = await api("/v1/chats", {
  method: "POST",
  headers: { authorization: `Bearer ${alice.tokens.access_token}` },
  body: JSON.stringify({ kind: "direct", peer_id: ghost.user.id }),
});

aliceWs.send({
  t: "send",
  d: { client_id: randomUUID(), chat_id: ghostChat.id, payload: { type: "text", text: "salom" } },
});
await settle();

const ghostMe = await api("/v1/me", {
  headers: { authorization: `Bearer ${ghost.tokens.access_token}` },
});
check("a device with a dead token still exists", ghostMe.devices.length === 1);

// Second message: the token was retired after the first failure, so nothing
// more should be attempted against it.
const beforeRetry = (await pushes()).length;
aliceWs.send({
  t: "send",
  d: { client_id: randomUUID(), chat_id: ghostChat.id, payload: { type: "text", text: "boz" } },
});
await settle();
check(
  "a retired token is not retried",
  (await pushes()).length === beforeRetry,
  "unregistered is authoritative",
);

aliceWs.socket.close();

const finalHealth = await (await fetch(`${WORKER}/health`)).json();
console.log(
  `\nworker: processed=${finalHealth.processed} sent=${finalHealth.sent} ` +
    `skippedOnline=${finalHealth.skippedOnline} retired=${finalHealth.retired}`,
);
check("the worker skipped at least one online device", finalHealth.skippedOnline >= 1);
check("the worker retired the dead token", finalHealth.retired >= 1);

console.log(failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) FAILED.\n`);
process.exit(failures === 0 ? 0 : 1);
