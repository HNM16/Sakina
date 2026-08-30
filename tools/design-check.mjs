#!/usr/bin/env node
/**
 * Is the design system still the only source of the design?
 *
 *   node tools/design-check.mjs
 *
 * `docs/BRAND.md` and `apps/mobile/lib/src/theme.dart` are the source of truth
 * for colour, and `layout.dart` for spacing. That is only true for as long as
 * nothing else names a colour. The failure is quiet and it is permanent: a hex
 * value typed into a widget keeps working, looks right on the day, and then
 * stops tracking the theme forever. Firuza moves, the app moves, and one
 * button does not — and nobody finds out from the code, they find out from a
 * screenshot months later.
 *
 * It is the exact failure mode this project is most exposed to. A model asked
 * to "make the badge blue" will very reasonably write `Color(0xFF32BBC8)` in
 * the badge, because that is a correct answer to the question it was asked and
 * a wrong answer to the question the codebase is asking.
 *
 * ## The rules
 *
 *   - Colour literals — `Color(0x…)`, `Color.fromARGB`, `Colors.<name>` — live
 *     in `theme.dart` and nowhere else.
 *   - A widget gets colour from `SakinaPalette.of(context)` or from
 *     `Theme.of(context).colorScheme`, both of which the theme controls.
 *
 * ## The deliberate exceptions
 *
 *   - `Colors.transparent` and `Colors.black`/`white` used *with an opacity*
 *     for a scrim or a shadow are not brand colour; they are the absence of
 *     colour, and routing them through the palette would say something untrue
 *     about them. Named here rather than waved through, so the list stays
 *     short and visible.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const lib = join(here, "..", "apps/mobile/lib");

let failures = 0;
function check(label, ok, detail = "") {
  if (!ok) failures += 1;
  console.log(`  ${ok ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
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

/**
 * Where the design is allowed to be defined.
 *
 * `src/ui/themes/` was added deliberately, which is the process BOUNDARIES.md
 * describes for crossing a boundary rather than working around it. A theme's
 * whole job is to decide colours; forcing every new one to add its palette to
 * theme.dart and its wiring somewhere else would split each theme across two
 * files, and a theme you cannot read in one place is a theme somebody gets
 * half-right.
 *
 * The rule that still holds, and is the one that matters: no colour anywhere
 * a *widget* can see it.
 */
const OWNER_FILES = new Set(["src/theme.dart", "src/layout.dart"]);
const OWNER_DIRS = ["src/ui/themes/"];
const owns = (short) =>
  OWNER_FILES.has(short) || OWNER_DIRS.some((dir) => short.startsWith(dir));

/** Shadows and scrims: absence of colour, not brand colour. */
const ALLOWED = [
  /Colors\.transparent/,
  /Colors\.(black|white)(\d*)?\.withOpacity/,
  /Colors\.(black|white)(12|26|38|45|54|70|87)\b/,
];

// Captures any trailing `.withOpacity(` so the allowances below can be tested
// against what the code actually says. Matching the bare literal and then
// asking whether it was followed by an opacity is a question the match cannot
// answer, which is how the scrim in message_actions.dart got flagged.
// The lookbehind matters: without it `Colors\.` also matches the tail of
// `SakinaColors.tileDay`, so every legitimate reference to our own tokens gets
// reported as a leak. It never fired while SakinaColors was only read inside
// theme.dart; the moment themes moved into their own files it flagged all of
// them.
const LITERAL =
  /(?:Color\(0x[0-9a-fA-F]{8}\)|Color\.fromARGB\(|(?<![A-Za-z])Colors\.[a-zA-Z0-9]+)(?:\.withOpacity\()?/g;

console.log("\nSakina design system\n");

const offenders = [];
let scanned = 0;

for (const file of dartFiles(lib)) {
  const short = relative(lib, file);
  if (owns(short)) continue;
  scanned += 1;

  const code = readFileSync(file, "utf8")
    .replace(/\/\/[^\n]*/g, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");

  for (const match of code.match(LITERAL) ?? []) {
    if (ALLOWED.some((allowed) => allowed.test(match))) continue;
    offenders.push(`${short}: ${match}`);
  }
}

check(
  "colour is defined in the theme and nowhere else",
  offenders.length === 0,
  offenders.length
    ? `${offenders.slice(0, 6).join("; ")}${offenders.length > 6 ? ` (+${offenders.length - 6})` : ""}`
    : `${scanned} files clean`,
);

// --- the typeface ---------------------------------------------------------
// `fontFamily` named a face the app never shipped, so Flutter asked the
// platform for it and rendered in whatever came back — a different typeface on
// every Android skin. It is a silent failure: the app looks fine to whoever is
// holding it, and wrong to everybody else.
const pubspec = readFileSync(join(lib, "..", "pubspec.yaml"), "utf8");
const declared = (readFileSync(join(lib, "src/theme.dart"), "utf8")
  .match(/static const fontFamily = '([^']+)'/) ?? [])[1];

check(
  "the typeface the theme names is actually bundled",
  Boolean(declared) && new RegExp(`family:\\s*${declared}\\b`).test(pubspec),
  declared
    ? `${declared} — declared in theme.dart and ${
        new RegExp(`family:\\s*${declared}\\b`).test(pubspec) ? "shipped" : "NOT in pubspec"
      }`
    : "theme.dart names no fontFamily",
);

// Every weight the app asks for has to exist as a real file. Flutter will
// happily synthesise a missing one by smearing the nearest, which looks like a
// rendering fault rather than a design.
const usedWeights = new Set(["400"]);
for (const file of dartFiles(lib)) {
  for (const [, w] of readFileSync(file, "utf8").matchAll(/FontWeight\.w(\d00)/g)) {
    usedWeights.add(w);
  }
}
const shipped = new Set([...pubspec.matchAll(/weight:\s*(\d+)/g)].map((m) => m[1]));
const unshipped = [...usedWeights].filter((w) => !shipped.has(w));
check(
  "every weight the app asks for is shipped, not synthesised",
  unshipped.length === 0,
  unshipped.length
    ? `missing ${unshipped.join(", ")} — Flutter would smear the nearest`
    : `${[...shipped].sort().join(", ")}`,
);

// The palette has to actually be reachable, or the rule above just pushes
// people to Theme.of(context) for everything and the palette rots.
const theme = readFileSync(join(lib, "src/theme.dart"), "utf8");
check(
  "SakinaPalette is exposed on the context",
  /static SakinaPalette of\(BuildContext/.test(theme),
  "SakinaPalette.of(context)",
);

console.log("");
console.log(failures === 0 ? "All checks passed.\n" : `${failures} check(s) failed.\n`);
process.exit(failures === 0 ? 0 : 1);
