#!/usr/bin/env node
/**
 * Does every part of the app stay out of every other part's way?
 *
 *   node tools/boundary-check.mjs
 *
 * The app is four sections — Chats, Calls, Explore, Profile — and the point of
 * splitting them was that each one can grow, be redesigned, or be rewritten
 * without disturbing the other three. That property is not something a
 * directory layout gives you. It is something a directory layout *suggests*,
 * right up until the first time somebody imports a widget from next door
 * because it was the quickest thing to do, and from then on the two sections
 * are one section with a folder between them.
 *
 * So it is checked.
 *
 * The deeper reason, which is worth writing down because it is not the usual
 * one: this codebase is edited by people and by models, and a model that has
 * misread a prompt does not fail loudly — it produces plausible code in the
 * wrong place. A boundary that is only a convention gives it nothing to hit. A
 * boundary that is checked turns "quietly broke something that worked" into a
 * failed build with a filename in it.
 *
 * ## The rules
 *
 *   ui/sections/<name>/   is owned by that section. Nothing else may import it,
 *                         and it may not import a sibling.
 *   ui/auth/              is the way in. Only main.dart may import it, and it
 *                         may not import a section — signing in must not be
 *                         able to break Chats, and Chats must not be able to
 *                         break signing in.
 *   ui/*.dart             is shared vocabulary — motion primitives, skeletons,
 *                         indicators, the empty state, the mark. Any section
 *                         may use it. It may not reach into a section.
 *   ui/sections/section.dart, ui/sections/sections.dart
 *                         the contract and the registry: the one seam the shell
 *                         and main.dart are allowed to know about.
 *
 * When a section genuinely needs something another one has, the answer is to
 * move that thing into `ui/` and make it shared vocabulary — deliberately,
 * where the next person can see it — rather than to reach sideways.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const lib = join(here, "..", "apps/mobile/lib");
const sectionsDir = join(lib, "src/ui/sections");

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

/** Which section a file belongs to, or null for shared code. */
function sectionOf(file) {
  const rel = relative(sectionsDir, file);
  if (rel.startsWith("..")) return null;
  const parts = rel.split("/");
  return parts.length > 1 ? parts[0] : null; // section.dart / sections.dart are shared
}

console.log("\nSakina boundaries\n");

const sections = readdirSync(sectionsDir).filter((entry) =>
  statSync(join(sectionsDir, entry)).isDirectory(),
);
console.log(`${sections.length} sections: ${sections.join(", ")}`);
console.log("");

const crossImports = [];
const reachIns = [];

for (const file of dartFiles(lib)) {
  const owner = sectionOf(file);
  const source = readFileSync(file, "utf8");

  for (const [, target] of source.matchAll(/^import\s+'([^']+)'/gm)) {
    if (target.startsWith("package:") || target.startsWith("dart:")) continue;

    const resolved = resolve(dirname(file), target);
    const targetOwner = sectionOf(resolved);
    if (targetOwner === null) continue; // shared vocabulary, always allowed

    const from = relative(lib, file);
    const to = relative(lib, resolved);

    if (owner === null) {
      // The registry's entire job is to import every section, and it is the
      // only file allowed to. Everything else goes through it.
      if (from === "src/ui/sections/sections.dart") continue;
      reachIns.push(`${from} -> ${to}`);
    } else if (owner !== targetOwner) {
      crossImports.push(`${from} -> ${to}`);
    }
  }
}

check(
  "no section imports another section",
  crossImports.length === 0,
  crossImports.length ? crossImports.join("; ") : `${sections.length} independent`,
);

check(
  "nothing outside the sections reaches into one",
  reachIns.length === 0,
  reachIns.length
    ? `${reachIns.join("; ")} — go through sections.dart instead`
    : "only the registry and the contract are public",
);

// --- auth ----------------------------------------------------------------
// The sign-in flow is the one path every user takes before anything else
// exists. It is kept sealed in both directions.
const authDir = join(lib, "src/ui/auth");
const authOutward = [];
const authInward = [];

for (const file of dartFiles(lib)) {
  const from = relative(lib, file);
  const inAuth = from.startsWith("src/ui/auth/");
  const source = readFileSync(file, "utf8");

  for (const [, target] of source.matchAll(/^import\s+'([^']+)'/gm)) {
    if (target.startsWith("package:") || target.startsWith("dart:")) continue;
    const to = relative(lib, resolve(dirname(file), target));

    if (inAuth && to.startsWith("src/ui/sections/")) authOutward.push(`${from} -> ${to}`);
    if (!inAuth && to.startsWith("src/ui/auth/") && from !== "main.dart") {
      authInward.push(`${from} -> ${to}`);
    }
  }
}

check(
  "the sign-in flow does not reach into a section",
  authOutward.length === 0,
  authOutward.length ? authOutward.join("; ") : "sealed outward",
);
check(
  "nothing but main.dart reaches into the sign-in flow",
  authInward.length === 0,
  authInward.length ? authInward.join("; ") : "sealed inward",
);

// A section that is not in the registry is a section nobody can reach.
const registry = readFileSync(join(sectionsDir, "sections.dart"), "utf8");
const unregistered = sections.filter((name) => !registry.includes(`${name}/`));
check(
  "every section directory is in the registry",
  unregistered.length === 0,
  unregistered.length ? `missing: ${unregistered.join(", ")}` : "sections.dart lists all",
);

console.log("");
console.log(failures === 0 ? "All checks passed.\n" : `${failures} check(s) failed.\n`);
process.exit(failures === 0 ? 0 : 1);
