#!/usr/bin/env node
/**
 * Does the layout actually survive every device we claim to run on?
 *
 *   node tools/device-matrix/verify.mjs
 *   node tools/device-matrix/verify.mjs --no-browser   (skip the rendering pass)
 *
 * Three passes, in increasing order of how much they can catch:
 *
 *   1. DRIFT — parse the constants out of apps/mobile/lib/src/layout.dart and
 *      confirm they still match devices.json. This is the check that matters
 *      most in a year: the matrix and the Dart are two files, and two files
 *      disagree eventually.
 *
 *   2. ARITHMETIC — run the layout rules at all 31 device widths and assert the
 *      invariants hold. Pure maths, no Flutter needed, which is the point: a
 *      layout arithmetic bug does not need an SDK, an emulator or a phone to
 *      find, and waiting for one is how it ships.
 *
 *   3. RENDERING — put a real browser at each device viewport and check for
 *      horizontal overflow, undersized tap targets, and Tajik strings that do
 *      not fit. The Flutter app cannot be compiled here; the dev client can,
 *      and it is built to the same breakpoints, so this is the closest thing to
 *      running the layout that this environment allows.
 *
 * What this does NOT prove: that the Flutter app renders correctly. Nothing
 * here compiles Dart. Pass 1 keeps the Dart honest about its own numbers and
 * pass 2 proves the rules are sound; the widgets themselves are still unverified,
 * same caveat as the rest of apps/mobile.
 */
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");

const matrix = JSON.parse(readFileSync(join(here, "devices.json"), "utf8"));
const layoutDart = readFileSync(join(root, "apps/mobile/lib/src/layout.dart"), "utf8");

let failures = 0;
function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

console.log("\nSakina device matrix\n");
console.log(`${matrix.devices.length} devices, ${matrix.breakpoints ? "" : "no "}breakpoints declared`);

// ---------------------------------------------------------------------------
// Pass 1 — drift between devices.json and layout.dart
// ---------------------------------------------------------------------------
console.log("\ndrift: layout.dart vs devices.json");

const constants = {};
for (const [, name, value] of layoutDart.matchAll(
  /static const double (\w+)\s*=\s*([\d.]+);/g,
)) {
  constants[name] = Number(value);
}

check(
  "layout.dart exposes its breakpoints as parseable constants",
  Object.keys(constants).length >= 5,
  `found ${Object.keys(constants).length}`,
);

const expected = {
  narrowWidth: matrix.breakpoints.narrow,
  compactWidth: matrix.breakpoints.compact,
  mediumWidth: matrix.breakpoints.medium,
  minTapTarget: matrix.minTapTarget,
  minSupportedWidth: matrix.minSupportedWidth,
};

for (const [name, want] of Object.entries(expected)) {
  check(
    `${name} agrees with the matrix`,
    constants[name] === want,
    `dart=${constants[name]} json=${want}`,
  );
}

// ---------------------------------------------------------------------------
// The layout rules, ported. Kept to the exact shape of the Dart so a reader can
// diff them by eye; pass 1 is what stops them silently disagreeing.
// ---------------------------------------------------------------------------
const NARROW = constants.narrowWidth;
const COMPACT = constants.compactWidth;
const MEDIUM = constants.mediumWidth;
const READABLE = constants.readableColumnWidth;
const TAP = constants.tapTarget;
const MAX_TEXT_SCALE = constants.maxTextScale;

function layoutFor(width) {
  const isNarrow = width < NARROW;
  const windowSize = width >= MEDIUM ? "expanded" : width >= COMPACT ? "medium" : "compact";
  const usesTwoPane = windowSize !== "compact";
  const listPaneWidth = usesTwoPane ? Math.min(Math.max(width * 0.36, 300), 400) : width;
  const detailPaneWidth = usesTwoPane ? width - listPaneWidth : width;
  const gutter = isNarrow ? 12 : 16;
  return {
    isNarrow,
    windowSize,
    usesTwoPane,
    listPaneWidth,
    detailPaneWidth,
    gutter,
    gap: isNarrow ? 10 : 14,
    avatarSize: isNarrow ? 40 : 48,
    contentMaxWidth: Math.min(detailPaneWidth, READABLE),
    bubbleMaxWidth: (available) =>
      Math.min(available * (isNarrow ? 0.86 : 0.78), READABLE * 0.8),
  };
}

// ---------------------------------------------------------------------------
// Pass 2 — the rules at every real width
// ---------------------------------------------------------------------------
console.log("\narithmetic: the rules at 31 real widths");

/**
 * The longest string the UI has to fit, in each language, measured in
 * characters. Tajik runs about a third longer than English and is nearly always
 * the binding constraint, which is the entire reason CLAUDE.md says to size
 * against it.
 */
const LONGEST = {
  ru: "Создать канал",
  tg: "Сохтани шабака",
  en: "Create channel",
};

let narrowest = null;
let widestPhone = 0;
const problems = [];

for (const device of matrix.devices) {
  const l = layoutFor(device.w);

  // Content has to fit between the gutters, and the safe-area insets on a
  // landscape notch come out of the same budget.
  const usable = device.w - l.gutter * 2;
  if (usable < 200) problems.push(`${device.name}: only ${usable} usable width`);

  // A bubble narrower than this cannot hold a word and a timestamp.
  const bubble = l.bubbleMaxWidth(usable);
  if (bubble < 180) problems.push(`${device.name}: bubble caps at ${Math.round(bubble)}`);

  // Two-pane must not produce a detail pane too narrow to be a conversation.
  if (l.usesTwoPane && l.detailPaneWidth < 320) {
    problems.push(`${device.name}: detail pane ${Math.round(l.detailPaneWidth)} < 320`);
  }

  // The vertical budget: app bar, composer, and both safe-area insets must
  // leave room for at least a few messages.
  const chrome = 56 + 56 + device.safeTop + device.safeBottom;
  if (device.h - chrome < 240) {
    problems.push(`${device.name}: only ${device.h - chrome} vertical for messages`);
  }

  if (narrowest === null || device.w < narrowest.w) narrowest = device;
  if (!l.usesTwoPane && device.w > widestPhone) widestPhone = device.w;
}

check("every device has usable width, bubble and vertical room", problems.length === 0,
  problems.length ? problems[0] : `narrowest ${narrowest.w}, widest phone ${widestPhone}`);

check("our own tap target clears the invariant", TAP >= matrix.minTapTarget,
  `${TAP} >= ${matrix.minTapTarget}`);

check("the 320 floor is inside the matrix", narrowest.w <= matrix.minSupportedWidth,
  `narrowest device is ${narrowest.w}`);

const foldOuter = matrix.devices.find((d) => d.name.includes("Fold outer"));
check("Fold outer screen is classified narrow", layoutFor(foldOuter.w).isNarrow,
  `${foldOuter.w} < ${NARROW}`);

const foldInner = matrix.devices.find((d) => d.name.includes("Fold inner"));
check("Fold inner screen gets two panes", layoutFor(foldInner.w).usesTwoPane,
  `${foldInner.w} >= ${COMPACT}`);

const biggestPhone = matrix.devices
  .filter((d) => d.w < COMPACT)
  .sort((a, b) => b.w - a.w)[0];
check("the widest phone stays single-pane", !layoutFor(biggestPhone.w).usesTwoPane,
  `${biggestPhone.name} at ${biggestPhone.w}`);

// A device that unfolds mid-conversation crosses the boundary in one frame.
check("the fold transition crosses exactly one breakpoint",
  layoutFor(foldOuter.w).windowSize === "compact" &&
    layoutFor(foldInner.w).windowSize === "medium",
  `${foldOuter.w} compact -> ${foldInner.w} medium`);

// ---------------------------------------------------------------------------
// Pass 3 — a real browser at every viewport
// ---------------------------------------------------------------------------
if (process.argv.includes("--no-browser")) {
  console.log("\n(rendering pass skipped)\n");
  process.exit(failures === 0 ? 0 : 1);
}

let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.log("\n  ! playwright not installed — rendering pass skipped");
  console.log("    pnpm add -Dw playwright\n");
  process.exit(failures === 0 ? 0 : 1);
}

const CLIENT = process.env.DEV_CLIENT_URL ?? "http://127.0.0.1:4002";
const executablePath = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";

const browser = await chromium.launch({
  headless: process.env.HEADED !== "1",
  ...(existsSync(executablePath) ? { executablePath } : {}),
  args: ["--no-sandbox"],
});

console.log("\nrendering: a real browser at each viewport");

const stamp = Date.now().toString().slice(-8);
const overflowing = [];
const tinyTargets = [];
const clipped = [];

// One signed-in session, resized across the matrix — the same thing a Fold does
// when it opens, and cheaper than 31 sign-ins.
const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await context.newPage();
page.on("pageerror", (err) => {
  console.log(`  ! page error: ${err.message}`);
  failures += 1;
});

await page.goto(CLIENT);
await page.fill("#email", `matrix${stamp}@example.com`);
await page.click("#go");
await page.waitForSelector("#bar:not(.hidden)", { timeout: 15_000 });

for (const device of matrix.devices) {
  await page.setViewportSize({ width: device.w, height: device.h });

  // Wait for transitions, not just for a frame. The matrix deliberately crosses
  // the two-pane breakpoint in both directions — that is what a Fold does when
  // it opens and closes — and a drawer sliding out takes 180ms. Measuring after
  // one frame catches it half-way and reports a layout bug that is not there.
  await page.evaluate(async () => {
    await new Promise((r) => requestAnimationFrame(() => r()));
    const aside = document.querySelector("aside");
    if (aside) {
      await Promise.all(
        aside.getAnimations({ subtree: true }).map((a) => a.finished.catch(() => {})),
      );
    }
    await new Promise((r) => requestAnimationFrame(() => r()));
  });

  const result = await page.evaluate(
    ({ minTap, longest }) => {
      const doc = document.documentElement;
      const overflow = doc.scrollWidth - doc.clientWidth;

      const small = [];
      for (const el of document.querySelectorAll("button, input, a[href], [role=button]")) {
        const r = el.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) continue; // hidden
        if (r.height < minTap - 0.5) {
          small.push(`${el.id || el.tagName.toLowerCase()} ${Math.round(r.height)}px`);
        }
      }

      // Does the longest label in each language fit the button it sits in?
      // Canvas measurement against the page's own font, so this reflects the
      // actual face rather than an estimate.
      const canvas = document.createElement("canvas");
      const ctx = canvas.getContext("2d");
      const probe = document.querySelector("button") || document.body;
      const style = getComputedStyle(probe);
      ctx.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
      const widths = {};
      for (const [lang, text] of Object.entries(longest)) {
        widths[lang] = ctx.measureText(text).width;
      }

      // How much of the viewport the chat list actually occupies. Width alone
      // is the wrong measure: below the breakpoint the list is a drawer that is
      // translated off-canvas, so it is 300px wide and takes up none of the
      // screen. What matters is its right edge.
      const aside = document.querySelector("aside");
      const asideRect = aside ? aside.getBoundingClientRect() : null;
      const asideOccupies = asideRect ? Math.max(0, Math.min(asideRect.right, window.innerWidth)) : 0;

      return { overflow, small, widths, asideOccupies, innerWidth: window.innerWidth };
    },
    { minTap: matrix.minTapTarget, longest: LONGEST },
  );

  if (result.overflow > 1) {
    overflowing.push(`${device.name} (${device.w}) overflows by ${Math.round(result.overflow)}px`);
  }
  if (result.small.length) {
    tinyTargets.push(`${device.name}: ${result.small.slice(0, 2).join(", ")}`);
  }

  // Tajik is the long one. If it does not fit the usable width at the maximum
  // text scale, the layout is sized against the wrong language.
  const l = layoutFor(device.w);
  const budget = (device.w - l.gutter * 2) / MAX_TEXT_SCALE;
  if (result.widths.tg > budget) {
    clipped.push(
      `${device.name}: "${LONGEST.tg}" needs ${Math.round(result.widths.tg)} of ${Math.round(budget)}`,
    );
  }

  // On a phone the conversation gets the whole screen and the list is a closed
  // drawer. On a tablet both are on screen and the list keeps its share.
  if (!l.usesTwoPane && result.asideOccupies > 1) {
    overflowing.push(
      `${device.name}: chat list occupies ${Math.round(result.asideOccupies)} of ${device.w} on a single-pane device`,
    );
  }
  if (l.usesTwoPane && result.asideOccupies < 200) {
    overflowing.push(
      `${device.name}: two-pane but the list only occupies ${Math.round(result.asideOccupies)}`,
    );
  }
}

check("no horizontal overflow at any device width", overflowing.length === 0,
  overflowing.length ? overflowing[0] : `${matrix.devices.length} viewports clean`);
check(`every control clears ${matrix.minTapTarget}px`, tinyTargets.length === 0,
  tinyTargets.length ? tinyTargets[0] : "all controls pass");
check("the longest Tajik label fits at maximum text scale", clipped.length === 0,
  clipped.length ? clipped[0] : `checked at ${MAX_TEXT_SCALE}x`);

await browser.close();

console.log(
  failures === 0
    ? "\nAll checks passed.\n"
    : `\n${failures} check(s) failed.\n`,
);
process.exit(failures === 0 ? 0 : 1);
