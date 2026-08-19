#!/usr/bin/env node
/**
 * Does every animation in the app have a path that removes it?
 *
 *   node tools/motion-check.mjs
 *
 * Guardrail G2 in the design-tells skill is explicit: motion without a
 * `prefers-reduced-motion` path is a defect, not a preference — and shortening
 * an animation is not the same as disabling it. `apps/mobile/lib/src/motion.dart`
 * exists so that branch is written once. Nothing enforced it, which is how a
 * guardrail decays: the first twelve widgets use the helper and the thirteenth
 * forgets, and nobody notices because the person who would notice has the
 * setting switched off.
 *
 * Two rules, both deliberately file-level rather than expression-level. A
 * precise rule would need a Dart parser; these are coarse enough to be honest
 * about what they check and strict enough to catch the actual failure, which is
 * somebody adding an animation and not thinking about the setting at all.
 *
 *   1. A file that animates must reference the reduce-motion gate.
 *   2. A `duration:` argument must come from the vocabulary, not from a
 *      hand-written Duration — otherwise rule 1 is satisfied by a file that
 *      gates one animation and hardcodes the next.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const lib = join(root, "apps/mobile/lib");

let failures = 0;
function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

function dartFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...dartFiles(full));
    else if (entry.endsWith(".dart")) out.push(full);
  }
  return out;
}

/** Anything that moves pixels over time. */
const ANIMATION_APIS = [
  "AnimationController",
  "TweenAnimationBuilder",
  "AnimatedContainer",
  "AnimatedOpacity",
  "AnimatedPadding",
  "AnimatedPositioned",
  "AnimatedAlign",
  "AnimatedSize",
  "AnimatedSwitcher",
  "AnimatedDefaultTextStyle",
  "AnimatedCrossFade",
  "SlideTransition",
  "FadeTransition",
  "ScaleTransition",
  "RotationTransition",
  "SizeTransition",
  ".animateTo(",
  ".repeat(",
  ".fling(",
];

/**
 * Expressions a `duration:` is allowed to be.
 *
 * `widget.duration` and `_duration` pass because they are parameters — the
 * value came from somewhere else, and that somewhere is subject to the same
 * rules. The vocabulary's own constants pass because reading
 * `SakinaMotion.travel` at a call site that is already gated is the intended
 * pattern.
 */
const ALLOWED_DURATION = [
  /SakinaMotion\.duration\s*\(/,
  /SakinaMotion\.(quick|base|travel|long|staggerWindow|pulse|typing|spin)\b/,
  /SakinaMotion\.staggerFor\s*\(/,
  /\.motion\s*\(/, // SakinaLayout.motion(), which gates internally
  /widget\.duration\b/,
  /Duration\.zero\b/,
  /_duration\b/,
];

/** The gate itself, in any of its forms. */
const GATE = /SakinaMotion\.(reduced|duration|curve|staggerFor)\s*\(|\.motion\s*\(|animationsDisabled|disableAnimations/;

/**
 * Files exempt from rule 1, with a reason each.
 *
 * motion.dart defines the gate, so requiring it to call itself is circular.
 * Nothing else is exempt; if this list grows, the rule is being worked around
 * rather than followed.
 */
const EXEMPT = new Set(["src/motion.dart"]);

console.log("\nSakina motion\n");

const files = dartFiles(lib);
const ungated = [];
const rawDurations = [];
let animatingFiles = 0;

for (const file of files) {
  const source = readFileSync(file, "utf8");
  const short = relative(lib, file);

  // Comments would otherwise satisfy the gate by talking about it.
  const code = source
    .replace(/\/\/[^\n]*/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");

  const animates = ANIMATION_APIS.some((api) => code.includes(api));
  if (!animates) continue;
  animatingFiles += 1;

  if (!EXEMPT.has(short) && !GATE.test(code)) {
    ungated.push(short);
  }

  // Rule 2. Every `duration:` argument, wherever it appears.
  for (const match of code.matchAll(/\bduration:\s*([^,\n)]+)/g)) {
    const expression = match[1].trim();
    if (EXEMPT.has(short)) continue;
    if (ALLOWED_DURATION.some((pattern) => pattern.test(expression))) continue;
    rawDurations.push(`${short}: duration: ${expression}`);
  }
}

console.log(`${files.length} files, ${animatingFiles} of them animate`);
console.log("");

check("every animating file reaches the reduce-motion gate", ungated.length === 0,
  ungated.length ? ungated.join(", ") : `${animatingFiles} files`);

check("every duration comes from the motion vocabulary", rawDurations.length === 0,
  rawDurations.length ? rawDurations.slice(0, 3).join(" | ") : "no hand-written durations");

// The vocabulary has to actually exist and export what the rules assume.
const motionSource = readFileSync(join(lib, "src/motion.dart"), "utf8");
for (const symbol of ["SakinaMotion", "SakinaHaptics", "reduced(", "staggerFor("]) {
  check(`motion.dart defines ${symbol.replace("(", "")}`, motionSource.includes(symbol));
}

// Returning exactly zero is the whole point of G2 — a short animation is still
// an animation. This catches somebody "fixing" a jarring cut by softening it.
check("the gate returns Duration.zero rather than something small",
  /reduced\(context\)\s*\?\s*Duration\.zero/.test(motionSource),
  "shortening is not disabling");

console.log(
  failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) failed.\n`,
);
process.exit(failures === 0 ? 0 : 1);
