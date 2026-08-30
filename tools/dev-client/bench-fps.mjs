#!/usr/bin/env node
/**
 * Frame rate under message load, measured in a real browser.
 *
 * "Smooth" is not an opinion, it is 16.7ms per frame. This drives the dev
 * client with a burst of incoming messages while sampling
 * `requestAnimationFrame`, and reports the numbers that actually decide whether
 * an app feels good:
 *
 *   - p50 frame time  — the typical case
 *   - p95 / p99       — the stutters people actually notice
 *   - dropped frames  — anything over 16.7ms at 60Hz
 *   - long frames     — over 50ms, which reads as a freeze
 *
 * Average FPS is deliberately not the headline. An app that renders 200 frames
 * at 4ms and 10 frames at 300ms averages out fine and feels broken.
 *
 *   node tools/dev-client/bench-fps.mjs
 *
 * The dev client is not the product — the real client is Flutter. But it runs
 * the same shape of code (render on every incoming frame), so the class of
 * problem it exposes is the same one, and here it is measurable.
 */
import { existsSync } from "node:fs";
import { randomUUID } from "node:crypto";

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error("\nNeeds Playwright:  pnpm add -Dw playwright\n");
  process.exit(1);
}

const URL = process.env.DEV_CLIENT_URL ?? "http://127.0.0.1:4002";
const API = process.env.API_URL ?? "http://127.0.0.1:4000";
const WS_URL = process.env.WS_URL ?? "ws://127.0.0.1:4001/ws";
const BURST = Number(process.env.BURST ?? 120);

/** CPU throttling, because the target device is a cheap Android, not a laptop. */
const CPU_SLOWDOWN = Number(process.env.CPU_SLOWDOWN ?? 4);

const executablePath = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";
const browser = await chromium.launch({
  headless: true,
  ...(existsSync(executablePath) ? { executablePath } : {}),
  args: ["--no-sandbox"],
});

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
      device: { device_id: deviceId, platform: "web", name: "bench" },
    }),
  });
  return { user, tokens, deviceId };
}

const stamp = Date.now().toString().slice(-8);

console.log("\nSakina frame-rate benchmark");
console.log(`  burst=${BURST} messages   cpu throttle=${CPU_SLOWDOWN}x\n`);

// Sender drives load over a raw socket; the browser tab is the thing measured.
const sender = await register(`bench-send${stamp}@example.com`);
const viewer = await register(`bench-view${stamp}@example.com`);

const chat = await api("/v1/chats", {
  method: "POST",
  headers: { authorization: `Bearer ${sender.tokens.access_token}` },
  body: JSON.stringify({ kind: "direct", peer_id: viewer.user.id }),
});

const context = await browser.newContext({ viewport: { width: 420, height: 780 } });
const page = await context.newPage();

// Emulating a slow device is the whole point: everything is 60fps on a laptop.
const cdp = await context.newCDPSession(page);
await cdp.send("Emulation.setCPUThrottlingRate", { rate: CPU_SLOWDOWN });

await page.goto(URL);
await page.fill("#email", `bench-view${stamp}@example.com`);
await page.click("#go");
await page.waitForFunction(() => document.getElementById("status")?.textContent === "online", {
  timeout: 20_000,
});
await page.waitForSelector(".chat", { timeout: 10_000 });
await page.click(".chat");

// Start sampling before the load begins.
//
// Two instruments, because they answer different questions. rAF deltas show
// what the user sees. Long tasks show *why* — a task blocking the main thread
// for 80ms is the cause; the dropped frames are the symptom.
await page.evaluate(() => {
  window.__frames = [];
  window.__longTasks = [];

  try {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__longTasks.push(entry.duration);
    }).observe({ entryTypes: ["longtask"] });
  } catch {
    // Not every build exposes longtask; the rAF numbers still stand.
  }

  let last = performance.now();
  const tick = (now) => {
    window.__frames.push(now - last);
    last = now;
    window.__raf = requestAnimationFrame(tick);
  };
  window.__raf = requestAnimationFrame(tick);
});

// Drive the burst from Node over a plain socket, so the load is not itself
// competing for the browser's main thread.
const WebSocket = (await import("ws")).default;
const socket = new WebSocket(WS_URL);

await new Promise((resolve, reject) => {
  socket.on("error", reject);
  socket.on("message", (raw) => {
    if (JSON.parse(raw.toString()).t === "ready") resolve();
  });
  socket.on("open", () =>
    socket.send(
      JSON.stringify({
        t: "hello",
        d: { v: 1, token: sender.tokens.access_token, device_id: sender.deviceId },
      }),
    ),
  );
});

const started = Date.now();
for (let i = 0; i < BURST; i += 1) {
  socket.send(
    JSON.stringify({
      t: "send",
      d: {
        client_id: randomUUID(),
        chat_id: chat.id,
        payload: { type: "text", text: `Паём рақами ${i + 1} — санҷиши суръат` },
      },
    }),
  );
  // Roughly a busy group chat rather than a flood, so this measures rendering
  // rather than the socket's buffer. The gateway's per-connection send limit
  // has to be raised for the run, or it throttles the load instead.
  await new Promise((r) => setTimeout(r, 25));
}

await new Promise((r) => setTimeout(r, 2500));
const elapsed = Date.now() - started;

const stats = await page.evaluate(() => {
  cancelAnimationFrame(window.__raf);
  // The first sample is measured from before the first paint; drop it.
  const frames = window.__frames.slice(1);
  const sorted = [...frames].sort((a, b) => a - b);
  const at = (q) => sorted[Math.floor(sorted.length * q)] ?? 0;
  const tasks = window.__longTasks ?? [];
  return {
    count: frames.length,
    p50: at(0.5),
    p95: at(0.95),
    p99: at(0.99),
    worst: sorted.at(-1) ?? 0,
    // A missed vsync, not float noise around 16.67. Anything past 25ms means a
    // frame was genuinely skipped.
    dropped: frames.filter((f) => f > 25).length,
    long: frames.filter((f) => f > 50).length,
    longTasks: tasks.length,
    longTaskTotal: tasks.reduce((a, b) => a + b, 0),
    longTaskWorst: tasks.length ? Math.max(...tasks) : 0,
    rendered: document.querySelectorAll(".msg").length,
  };
});

const socketOpen = socket.readyState === 1;
socket.close();
await browser.close();

const pct = (n) => ((n / stats.count) * 100).toFixed(1);

console.log(`  messages rendered   ${stats.rendered}`);
console.log(`  frames sampled      ${stats.count} over ${elapsed}ms`);
console.log("");
console.log(`  p50 frame time      ${stats.p50.toFixed(1)}ms`);
console.log(`  p95 frame time      ${stats.p95.toFixed(1)}ms`);
console.log(`  p99 frame time      ${stats.p99.toFixed(1)}ms`);
console.log(`  worst frame         ${stats.worst.toFixed(1)}ms`);
console.log("");
console.log(`  dropped (>25ms)     ${stats.dropped}  (${pct(stats.dropped)}%)`);
console.log(`  janky  (>50ms)      ${stats.long}  (${pct(stats.long)}%)`);
console.log("");
console.log(`  long tasks          ${stats.longTasks}  (worst ${stats.longTaskWorst.toFixed(0)}ms,` +
  ` ${stats.longTaskTotal.toFixed(0)}ms blocked in total)`);

// 60fps is the bar. p95 is the honest measure of whether it is met — a p50 of
// 8ms means nothing if one frame in twenty takes 200ms.
// The bar. Not "zero dropped frames" — garbage collection alone will cost you
// one occasionally and chasing that is not engineering. What matters is that
// drops stay rare, nothing ever freezes, and no single task blocks long enough
// to be felt as a stutter.
const droppedPct = (stats.dropped / stats.count) * 100;
const smooth = droppedPct < 1 && stats.long === 0 && stats.longTaskWorst < 50;
console.log(
  `\n  ${smooth ? "✓" : "✗"} 60fps: ${droppedPct.toFixed(1)}% dropped (<1%), ` +
    `${stats.long} frozen, worst block ${stats.longTaskWorst.toFixed(0)}ms\n`,
);

if (!socketOpen) console.log("  ! sender socket closed early — result may be short\n");
process.exit(smooth ? 0 : 1);
