#!/usr/bin/env node
/**
 * Rebuilds the bundled typeface from a full source font.
 *
 *   node tools/build-fonts.mjs /path/to/IBMPlexSans-{weight}.ttf
 *   node tools/build-fonts.mjs           # finds them via fontconfig
 *
 * The app ships IBM Plex Sans rather than asking the phone for a family name
 * and hoping. What it ships is a *subset*: the glyphs this app can plausibly
 * need, and none of the several thousand it cannot.
 *
 * ## What goes in the subset, and why it is generous
 *
 * Latin, Latin-1, Latin Extended-A and the entire Cyrillic block. The obvious
 * subset is "the languages we support", which would be about 200 characters
 * and would be wrong: a messenger receives text nobody planned for. A contact
 * named in Ukrainian, a forwarded line of Polish, a Kazakh place name — each
 * would fall back to a system face mid-word, which is precisely the "looks
 * foreign" failure the bundle exists to prevent. The whole Cyrillic block
 * costs a few KB over the narrow version.
 *
 * Anything genuinely outside it — emoji, CJK, Perso-Arabic — still falls back,
 * and must. No app can subset its way out of receiving a script it has never
 * heard of.
 *
 * ## Requires
 *
 * fonttools (`pip install fonttools`). Not a repo dependency: this runs when
 * somebody changes the typeface, which is roughly never.
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(here, "..", "apps/mobile/assets/fonts");

/** Weight name in the source file → the CSS weight pubspec.yaml declares. */
const WEIGHTS = [
  ["Regular", 400],
  ["Medium", 500],
  ["SemiBold", 600],
  ["Bold", 700],
];

const RANGES = [
  [0x0020, 0x007e], // ASCII printable
  [0x00a0, 0x00ff], // Latin-1: accented Western European
  [0x0100, 0x017f], // Latin Extended-A: Polish, Czech, Turkish, Baltic
  [0x0400, 0x04ff], // Cyrillic, the whole block — Tajik's six live here
  [0x0500, 0x052f], // Cyrillic supplement
  [0x2010, 0x203a], // dashes, quotes, ellipsis
];
const EXTRA = "€₽₸₴№•·✓✔←→↑↓°±×÷≈™";

function subsetText() {
  let out = "";
  for (const [a, b] of RANGES) {
    for (let c = a; c <= b; c += 1) out += String.fromCodePoint(c);
  }
  return out + EXTRA;
}

/** Ask fontconfig for the source file, matching the basename exactly. */
function locate(stem) {
  const listed = execFileSync("fc-list", ["--format", "%{file}\n"], { encoding: "utf8" });
  for (const line of listed.split("\n")) {
    const file = line.trim();
    if (!file) continue;
    const base = file.slice(file.lastIndexOf("/") + 1);
    const dot = base.lastIndexOf(".");
    // Exact, not substring: `IBMPlexSans-Bold` must not match
    // `IBMPlexSans-BoldItalic`, which is how the first type specimen for this
    // project came out entirely in italics.
    if (base.slice(0, dot) === stem && [".ttf", ".otf"].includes(base.slice(dot))) {
      return file;
    }
  }
  return null;
}

try {
  execFileSync("pyftsubset", ["--help"], { stdio: "ignore" });
} catch {
  console.error("\n  pyftsubset not found. `pip install fonttools`\n");
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });
const textFile = join(outDir, ".subset.txt");
execFileSync("bash", ["-c", `cat > ${textFile}`], { input: subsetText() });

console.log("\nSakina fonts\n");
let total = 0;
for (const [stem, weight] of WEIGHTS) {
  const source = locate(`IBMPlexSans-${stem}`);
  if (!source) {
    console.error(`  ✗ IBMPlexSans-${stem} not installed — apt install fonts-ibm-plex`);
    process.exit(1);
  }
  const out = join(outDir, `IBMPlexSans-${stem}.ttf`);
  execFileSync("pyftsubset", [
    source,
    `--text-file=${textFile}`,
    "--layout-features=*",
    "--hinting",
    "--name-IDs=*",
    `--output-file=${out}`,
  ]);
  const kb = Math.round(statSync(out).size / 1024);
  total += kb;
  console.log(`  ✓ w${weight}  ${`IBMPlexSans-${stem}.ttf`.padEnd(30)} ${String(kb).padStart(4)} KB`);
}
execFileSync("rm", ["-f", textFile]);
console.log(`  ${"".padEnd(36)} ${String(total).padStart(4)} KB total\n`);
console.log("Declared in apps/mobile/pubspec.yaml under flutter: fonts:\n");
