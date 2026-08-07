#!/usr/bin/env node
/**
 * M0 definition of done, as an executable check.
 *
 * Two users register, open a direct chat and exchange a message. Then the
 * awkward cases that a messenger on Tajik mobile data actually hits: a retry of
 * a message whose ack never arrived, and a client that went offline and has to
 * catch up.
 *
 * Usage (with the stack running):
 *   node services/gateway/scripts/e2e-smoke.mjs
 */
import WebSocket from "ws";
import { randomUUID } from "node:crypto";

const API = process.env.API_URL ?? "http://127.0.0.1:4000";
const WS_URL = process.env.WS_URL ?? "ws://127.0.0.1:4001/ws";

let failures = 0;

function check(label, condition, detail = "") {
  const mark = condition ? "✓" : "✗";
  if (!condition) failures += 1;
  console.log(`  ${mark} ${label}${detail ? ` — ${detail}` : ""}`);
}

async function api(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    ...options,
    headers: { "content-type": "application/json", ...(options.headers ?? {}) },
  });
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${path} -> ${res.status} ${text}`);
  return body;
}

async function register(phone, deviceName) {
  const deviceId = randomUUID();
  const { dev_code } = await api("/v1/auth/otp/request", {
    method: "POST",
    body: JSON.stringify({ phone }),
  });
  if (!dev_code) throw new Error("API is not in OTP dev mode; cannot run smoke test");

  const { user, tokens } = await api("/v1/auth/otp/verify", {
    method: "POST",
    body: JSON.stringify({
      phone,
      code: dev_code,
      device: { device_id: deviceId, platform: "android", name: deviceName },
    }),
  });

  return { user, tokens, deviceId };
}

/** A socket wrapper that lets a test await a specific frame type. */
function connect(session) {
  const socket = new WebSocket(WS_URL);
  const inbox = [];
  const waiters = [];

  const client = {
    socket,
    inbox,
    send: (frame) => socket.send(JSON.stringify(frame)),
    close: () => socket.close(),
    /** Resolves with the next frame of `type` matching `predicate`. */
    next(type, predicate = () => true, timeoutMs = 5000) {
      const existing = inbox.findIndex((f) => f.t === type && predicate(f));
      if (existing !== -1) return Promise.resolve(inbox.splice(existing, 1)[0]);

      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const i = waiters.indexOf(waiter);
          if (i !== -1) waiters.splice(i, 1);
          reject(new Error(`timed out waiting for "${type}" frame`));
        }, timeoutMs);
        const waiter = { type, predicate, resolve, timer };
        waiters.push(waiter);
      });
    },
  };

  socket.on("message", (raw) => {
    const frame = JSON.parse(raw.toString());
    const i = waiters.findIndex((w) => w.type === frame.t && w.predicate(frame));
    if (i !== -1) {
      const [waiter] = waiters.splice(i, 1);
      clearTimeout(waiter.timer);
      waiter.resolve(frame);
    } else {
      inbox.push(frame);
    }
  });

  return new Promise((resolve, reject) => {
    socket.on("error", reject);
    socket.on("open", () => {
      client.send({
        t: "hello",
        d: { v: 1, token: session.tokens.access_token, device_id: session.deviceId },
      });
      client.next("ready").then((ready) => resolve({ ...client, ready }), reject);
    });
  });
}

const suffix = Date.now().toString().slice(-7);
const phoneA = `+9929${suffix}`;
const phoneB = `+9928${suffix}`;

console.log("\nSakina M0 smoke test\n");

// --- registration ---------------------------------------------------------
console.log("auth");
const alice = await register(phoneA, "Alice Android");
const bob = await register(phoneB, "Bob Android");
check("two users registered via phone + OTP", !!alice.user.id && !!bob.user.id);
check("users are distinct", alice.user.id !== bob.user.id);

// --- chat creation --------------------------------------------------------
console.log("\nchats");
const chat = await api("/v1/chats", {
  method: "POST",
  headers: { authorization: `Bearer ${alice.tokens.access_token}` },
  body: JSON.stringify({ kind: "direct", peer_id: bob.user.id }),
});
check("direct chat created", chat.kind === "direct");
check("chat has both members", chat.members.length === 2, `${chat.members.length} members`);

const again = await api("/v1/chats", {
  method: "POST",
  headers: { authorization: `Bearer ${alice.tokens.access_token}` },
  body: JSON.stringify({ kind: "direct", peer_id: bob.user.id }),
});
check("reopening a direct chat returns the same thread", again.id === chat.id);

// --- realtime delivery ----------------------------------------------------
console.log("\nrealtime");
const aliceWs = await connect(alice);
const bobWs = await connect(bob);
check("both clients received `ready`", !!aliceWs.ready && !!bobWs.ready);
check(
  "`ready` carries the chat list",
  aliceWs.ready.d.chats.some((c) => c.id === chat.id),
);

const clientId = randomUUID();
// Tajik Cyrillic on the wire — the alphabet the app actually has to carry.
const tajikText = "Салом! Ту чӣ хел? Ин аввалин паём дар Сакина аст. 🇹🇯";

aliceWs.send({
  t: "send",
  d: { client_id: clientId, chat_id: chat.id, payload: { type: "text", text: tajikText } },
});

const ack = await aliceWs.next("sent");
check("sender got an ack with a server-assigned seq", ack.d.seq === 1, `seq=${ack.d.seq}`);

const delivered = await bobWs.next("message");
check("recipient received the message", delivered.d.id === ack.d.id);
check("Tajik Cyrillic survived the round trip", delivered.d.payload.text === tajikText);
check("recipient sees the same seq", delivered.d.seq === ack.d.seq);

// --- idempotency ----------------------------------------------------------
console.log("\nidempotency (the flaky-network case)");
// Alice's ack was lost on a bad connection, so the client retries the exact
// same client_id. The user must not end up having sent it twice.
aliceWs.send({
  t: "send",
  d: { client_id: clientId, chat_id: chat.id, payload: { type: "text", text: tajikText } },
});
const reack = await aliceWs.next("sent");
check("retry returns the original seq, not a new one", reack.d.seq === ack.d.seq);
check("retry returns the original message id", reack.d.id === ack.d.id);

await new Promise((r) => setTimeout(r, 300));
check(
  "retry produced no duplicate for the recipient",
  bobWs.inbox.filter((f) => f.t === "message").length === 0,
  `${bobWs.inbox.filter((f) => f.t === "message").length} extra message frames`,
);

// --- offline catch-up -----------------------------------------------------
console.log("\noffline catch-up (the airplane-mode case)");
bobWs.close();
await new Promise((r) => setTimeout(r, 200));

for (const text of ["Паёми дуюм", "Паёми сеюм"]) {
  aliceWs.send({
    t: "send",
    d: { client_id: randomUUID(), chat_id: chat.id, payload: { type: "text", text } },
  });
  await aliceWs.next("sent");
}

const bobBack = await connect(bob);
bobBack.send({ t: "sync", d: { cursors: [{ chat_id: chat.id, last_seq: 1 }] } });
const synced = await bobBack.next("sync");
check("reconnect returned the missed messages", synced.d.messages.length === 2, `got ${synced.d.messages.length}`);
check(
  "missed messages are in seq order",
  synced.d.messages[0].seq === 2 && synced.d.messages[1].seq === 3,
);
check("no more history pending", synced.d.has_more === false);

// --- read receipts --------------------------------------------------------
console.log("\nread receipts");
bobBack.send({ t: "read", d: { chat_id: chat.id, up_to_seq: 3 } });
const receipt = await aliceWs.next("read");
check("sender was told the message was read", receipt.d.up_to_seq === 3);
check("receipt identifies the reader", receipt.d.user_id === bob.user.id);

// --- authorization --------------------------------------------------------
console.log("\nauthorization");
const mallory = await register(`+9927${suffix}`, "Mallory");
const malloryWs = await connect(mallory);
malloryWs.send({
  t: "send",
  d: { client_id: randomUUID(), chat_id: chat.id, payload: { type: "text", text: "let me in" } },
});
const denied = await malloryWs.next("error");
check("non-member cannot post to a chat", denied.d.code === "forbidden", denied.d.message);

const histRes = await fetch(`${API}/v1/chats/${chat.id}/messages`, {
  headers: { authorization: `Bearer ${mallory.tokens.access_token}` },
});
check("non-member cannot read history over HTTP", histRes.status === 403, `status ${histRes.status}`);

const noAuth = await fetch(`${API}/v1/chats`);
check("unauthenticated request is rejected", noAuth.status === 401, `status ${noAuth.status}`);

// --- history over HTTP ----------------------------------------------------
console.log("\nhistory");
const history = await api(`/v1/chats/${chat.id}/messages?limit=50`, {
  headers: { authorization: `Bearer ${bob.tokens.access_token}` },
});
check("history returns all three messages", history.messages.length === 3, `got ${history.messages.length}`);
check(
  "history is gapless and ordered",
  history.messages.every((m, i) => m.seq === i + 1),
);

aliceWs.close();
bobBack.close();
malloryWs.close();

console.log(failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) FAILED.\n`);
process.exit(failures === 0 ? 0 : 1);
