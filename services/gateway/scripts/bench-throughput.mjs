#!/usr/bin/env node
/**
 * How much the gateway can take, and where the time goes.
 *
 * Measures end-to-end message latency — the time from a sender putting a frame
 * on the wire to the recipient's socket seeing it — under concurrent load, plus
 * raw send throughput.
 *
 * Latency percentiles are the point, not the average. A messenger that is
 * usually 8ms and occasionally 900ms feels broken, and an average hides that
 * completely.
 *
 *   node services/gateway/scripts/bench-throughput.mjs
 *
 * Needs api :4000 and gateway :4001, with SEND_RATE_LIMIT raised — otherwise
 * this measures the rate limiter rather than the server.
 */
import WebSocket from "ws";
import { randomUUID } from "node:crypto";

const API = process.env.API_URL ?? "http://127.0.0.1:4000";
const WS_URL = process.env.WS_URL ?? "ws://127.0.0.1:4001/ws";

/** Concurrent conversations, each a sender and a receiver on their own socket. */
const PAIRS = Number(process.env.PAIRS ?? 20);
const PER_PAIR = Number(process.env.PER_PAIR ?? 50);

/**
 * Messages per second to offer in the latency phase.
 *
 * Deliberately a realistic figure rather than a flood. Ten thousand users
 * sending twenty messages a day averages roughly 2/s; even a twentyfold peak is
 * around 50/s. Measuring latency at 4000/s tells you what a saturated queue
 * looks like, not what a user would experience.
 */
const TARGET_RATE = Number(process.env.TARGET_RATE ?? 100);

async function api(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    ...options,
    headers: { "content-type": "application/json", ...(options.headers ?? {}) },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path} -> ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

async function register(email) {
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
      device: { device_id: deviceId, platform: "android", name: "bench" },
    }),
  });
  return { user, tokens, deviceId };
}

function connect(session, onFrame) {
  const socket = new WebSocket(WS_URL);
  return new Promise((resolve, reject) => {
    socket.on("error", reject);
    socket.on("message", (raw) => {
      const frame = JSON.parse(raw.toString());
      if (frame.t === "ready") return resolve(socket);
      onFrame(frame);
    });
    socket.on("open", () =>
      socket.send(
        JSON.stringify({
          t: "hello",
          d: { v: 1, token: session.tokens.access_token, device_id: session.deviceId },
        }),
      ),
    );
  });
}

const percentile = (sorted, q) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * q))] ?? 0;

const stamp = Date.now().toString().slice(-8);

console.log("\nSakina gateway throughput");
console.log(`  ${PAIRS} concurrent chats × ${PER_PAIR} messages = ${PAIRS * PER_PAIR} total\n`);

process.stdout.write("  setting up… ");
const pairs = [];
for (let i = 0; i < PAIRS; i += 1) {
  const sender = await register(`bs${stamp}x${i}@example.com`);
  const receiver = await register(`br${stamp}x${i}@example.com`);
  const chat = await api("/v1/chats", {
    method: "POST",
    headers: { authorization: `Bearer ${sender.tokens.access_token}` },
    body: JSON.stringify({ kind: "direct", peer_id: receiver.user.id }),
  });
  pairs.push({ sender, receiver, chat });
}
console.log(`${PAIRS} chats ready`);

const latencies = [];
const ackLatencies = [];
const sentAt = new Map();
let received = 0;

const expected = PAIRS * PER_PAIR;
let resolveDone;
const done = new Promise((r) => (resolveDone = r));
// Reused by the saturation phase, which counts to a different total.
let satResolver = null;
let satTarget = 0;

for (const pair of pairs) {
  pair.receiverSocket = await connect(pair.receiver, (frame) => {
    if (frame.t !== "message") return;
    const start = sentAt.get(frame.d.client_id);
    if (start !== undefined) latencies.push(Number(process.hrtime.bigint() - start) / 1e6);
    received += 1;
    if (satResolver) {
      if (received >= satTarget) satResolver();
    } else if (received >= expected) {
      resolveDone();
    }
  });

  pair.senderSocket = await connect(pair.sender, (frame) => {
    if (frame.t !== "sent") return;
    const start = sentAt.get(frame.d.client_id);
    if (start !== undefined) ackLatencies.push(Number(process.hrtime.bigint() - start) / 1e6);
  });
}

function send(pair, index) {
  const clientId = randomUUID();
  sentAt.set(clientId, process.hrtime.bigint());
  pair.senderSocket.send(
    JSON.stringify({
      t: "send",
      d: {
        client_id: clientId,
        chat_id: pair.chat.id,
        payload: { type: "text", text: `Паём ${index} санҷиш` },
      },
    }),
  );
}

console.log(`  phase 1: latency at ${TARGET_RATE} msg/s (realistic load)\n`);
const started = process.hrtime.bigint();

// Paced to a rate the server can comfortably serve. This measures the server;
// flooding it would measure the queue that forms in front of it.
const gapMs = 1000 / TARGET_RATE;
let index = 0;
for (let round = 0; round < PER_PAIR; round += 1) {
  for (const pair of pairs) {
    send(pair, index++);
    await new Promise((r) => setTimeout(r, gapMs));
  }
}

const timeout = new Promise((r) => setTimeout(() => r("timeout"), 20_000));
const outcome = await Promise.race([done, timeout]);
const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;

const sortedE2e = [...latencies].sort((a, b) => a - b);
const sortedAck = [...ackLatencies].sort((a, b) => a - b);

console.log(`  delivered           ${received}/${expected}${outcome === "timeout" ? "  (TIMED OUT)" : ""}`);
console.log(`  wall clock          ${elapsedMs.toFixed(0)}ms`);
console.log(`  throughput          ${(received / (elapsedMs / 1000)).toFixed(0)} msg/s delivered`);
console.log("");
console.log("  ack latency (send → server assigned a seq)");
console.log(`    p50               ${percentile(sortedAck, 0.5).toFixed(1)}ms`);
console.log(`    p95               ${percentile(sortedAck, 0.95).toFixed(1)}ms`);
console.log(`    p99               ${percentile(sortedAck, 0.99).toFixed(1)}ms`);
console.log(`    worst             ${(sortedAck.at(-1) ?? 0).toFixed(1)}ms`);
console.log("");
console.log("  end-to-end latency (sender's wire → recipient's socket)");
console.log(`    p50               ${percentile(sortedE2e, 0.5).toFixed(1)}ms`);
console.log(`    p95               ${percentile(sortedE2e, 0.95).toFixed(1)}ms`);
console.log(`    p99               ${percentile(sortedE2e, 0.99).toFixed(1)}ms`);
console.log(`    worst             ${(sortedE2e.at(-1) ?? 0).toFixed(1)}ms`);

// A message that takes longer than a couple of hundred ms to cross reads as lag
// in a conversation, even though nothing has failed.
// Saturation: how fast can it go at all. Offered as fast as the sockets accept,
// so the result is the server's ceiling rather than a paced rate.
console.log("\n  phase 2: saturation\n");

// Phase-1 percentiles are already computed above; safe to reset the counters.
received = 0;
sentAt.clear();
const satExpected = PAIRS * 20;
let resolveSat;
const satDone = new Promise((r) => (resolveSat = r));
satResolver = resolveSat;
satTarget = satExpected;

const satStart = process.hrtime.bigint();
await Promise.all(
  pairs.map(async (pair) => {
    for (let i = 0; i < 20; i += 1) send(pair, i);
  }),
);
await Promise.race([satDone, new Promise((r) => setTimeout(r, 20_000))]);
const satMs = Number(process.hrtime.bigint() - satStart) / 1e6;

console.log(`  saturation          ${(received / (satMs / 1000)).toFixed(0)} msg/s`);
console.log(`  headroom            ~${Math.round(received / (satMs / 1000) / 50)}x a busy-hour`);
console.log(`                      peak for 10k users (~50 msg/s)`);

// Latency at realistic load is the number that matters. A conversation feels
// live below about 250ms end to end.
for (const pair of pairs) {
  pair.senderSocket.close();
  pair.receiverSocket.close();
}

const healthy = percentile(sortedE2e, 0.99) < 250;
console.log(
  `\n  ${healthy ? "✓" : "✗"} p99 end-to-end ${percentile(sortedE2e, 0.99).toFixed(0)}ms ` +
    `at ${TARGET_RATE} msg/s${healthy ? "" : " — over the 250ms budget"}\n`,
);

process.exit(healthy ? 0 : 1);
