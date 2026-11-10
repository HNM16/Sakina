#!/usr/bin/env node
/**
 * Drives two real browser tabs through the dev client, so "it works" means a
 * message actually crossed between two browsers rather than a script asserting
 * against an API.
 *
 * This is the check that the dev client itself is not broken — the protocol is
 * already covered by services/gateway/scripts/e2e-smoke.mjs.
 *
 *   node tools/dev-client/verify.mjs
 *
 * Needs the full stack up: postgres, redis, api, gateway, and the dev client
 * server on :4002. Chromium comes from PLAYWRIGHT_BROWSERS_PATH.
 */
import { existsSync } from "node:fs";

// Playwright is not a dependency of the repo — it would pull a browser download
// on every install for a check most people run once. Install it on demand.
let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error(
    "\nThis check needs Playwright:\n\n" +
      "  pnpm add -Dw playwright\n\n" +
      "If a browser is already on the machine, point at it instead of downloading:\n" +
      "  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 pnpm add -Dw playwright\n" +
      "  CHROMIUM_PATH=/path/to/chrome node tools/dev-client/verify.mjs\n",
  );
  process.exit(1);
}

const URL = process.env.DEV_CLIENT_URL ?? "http://127.0.0.1:4002";
const HEADLESS = process.env.HEADED !== "1";

let failures = 0;
function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

// The sandbox ships a Chromium at a fixed path that may not match the version
// this Playwright build expects, so point at it explicitly rather than letting
// Playwright go looking for a download it is not allowed to make.
const executablePath = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";
const browser = await chromium.launch({
  headless: HEADLESS,
  ...(existsSync(executablePath) ? { executablePath } : {}),
  args: ["--no-sandbox"],
});

/** A separate context per user — separate sessionStorage, so separate devices. */
async function openTab(email) {
  const context = await browser.newContext();
  const page = await context.newPage();
  page.on("pageerror", (err) => {
    console.log(`  ! page error (${email}): ${err.message}`);
    failures += 1;
  });

  await page.goto(URL);
  await page.fill("#email", email);
  await page.click("#go");
  await page.waitForSelector("#bar:not(.hidden)", { timeout: 10_000 });
  await page.waitForFunction(() => document.getElementById("status").textContent === "online", {
    timeout: 10_000,
  });

  const userId = await page.evaluate(() => window.__sakina.state().userId);
  return { context, page, userId, email };
}

const stamp = Date.now().toString().slice(-8);

console.log("\nSakina dev client — two real browsers\n");
console.log("sign in");

const alice = await openTab(`alice${stamp}@example.com`);
const bob = await openTab(`bob${stamp}@example.com`);
check("both tabs signed in and connected", !!alice.userId && !!bob.userId);
check("they are different accounts", alice.userId !== bob.userId);

console.log("\nstart a chat");
await alice.page.fill("#peer", bob.userId);
await alice.page.click("#newChat button");
await alice.page.waitForSelector(".chat.active", { timeout: 5000 });
check("Alice opened a direct chat with Bob", true);

console.log("\nsend a message");
const tajik = "Салом Фаррух! Ин паём аз браузер меояд. 🇹🇯";
await alice.page.fill("#text", tajik);
await alice.page.click("#sendBtn");

// Alice sees it immediately — before any ack — because the client renders local
// state first.
await alice.page.waitForSelector(".msg.mine", { timeout: 3000 });
check("sender sees the bubble straight away", true);

// And then it settles to sent once the server assigns a seq.
await alice.page.waitForFunction(
  () => {
    const el = document.querySelector(".msg.mine");
    return el && !el.classList.contains("pending");
  },
  { timeout: 5000 },
);
const aliceSeq = await alice.page.getAttribute(".msg.mine", "data-seq");
check("it was acked with a server seq", aliceSeq === "1", `seq=${aliceSeq}`);

// Bob's tab receives it with no interaction at all.
await bob.page.waitForSelector(".chat", { timeout: 8000 });
await bob.page.click(".chat");
await bob.page.waitForSelector(".msg", { timeout: 5000 });
const received = await bob.page.textContent(".msg");
check("Bob's tab received it over the socket", received.includes("Салом Фаррух"));
check("Tajik Cyrillic survived the browser round trip", received.includes("🇹🇯"));

console.log("\nreply");
await bob.page.fill("#text", "Салом! Ҳа, расид.");
await bob.page.click("#sendBtn");
await alice.page.waitForFunction(
  () => document.querySelectorAll(".msg").length >= 2,
  { timeout: 8000 },
);
const aliceMsgs = await alice.page.$$eval(".msg", (els) => els.map((e) => e.textContent));
check("Alice received the reply", aliceMsgs.some((m) => m.includes("расид")));

console.log("\noffline, then back");
// Kill Bob's socket and send while he is away. This is the case the whole
// seq-based sync design exists for.
await bob.page.evaluate(() => window.__sakina.dropSocket());
await bob.page.waitForFunction(
  () => document.getElementById("status").textContent !== "online",
  { timeout: 5000 },
);
check("Bob's tab shows it is offline", true);

await alice.page.fill("#text", "Паёми ҳангоми офлайн");
await alice.page.click("#sendBtn");
await alice.page.waitForTimeout(500);

// The client reconnects on its own; no reload, no re-login.
await bob.page.waitForFunction(
  () => document.getElementById("status").textContent === "online",
  { timeout: 15_000 },
);
await bob.page.waitForFunction(
  () => document.querySelectorAll(".msg").length >= 3,
  { timeout: 10_000 },
);
const bobAfter = await bob.page.$$eval(".msg", (els) => els.map((e) => e.textContent));
check(
  "the missed message arrived after reconnect",
  bobAfter.some((m) => m.includes("офлайн")),
  `${bobAfter.length} messages`,
);

console.log("\nordering");
const seqs = await bob.page.$$eval(".msg", (els) =>
  els.map((e) => Number(e.getAttribute("data-seq"))),
);
check(
  "messages are gapless and in order",
  seqs.every((s, i) => s === i + 1),
  seqs.join(","),
);

await browser.close();
console.log(failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) FAILED.\n`);
process.exit(failures === 0 ? 0 : 1);
