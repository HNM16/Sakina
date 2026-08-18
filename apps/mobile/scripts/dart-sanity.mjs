#!/usr/bin/env node
/**
 * The cheapest possible stand-in for a compiler.
 *
 *   node apps/mobile/scripts/dart-sanity.mjs
 *
 * There is no Flutter SDK in this environment, so none of `apps/mobile` can be
 * compiled or run here. That is a real limitation and this script does not
 * pretend otherwise — `dart analyze` would catch strictly more. What it does
 * catch is the class of mistake that comes from editing Dart without a compiler
 * in the loop:
 *
 *   - an import pointing at a file that does not exist, usually after a rename;
 *   - a `package:` import whose package is not in pubspec.yaml, which fails at
 *     `pub get` rather than at the edit that caused it;
 *   - unbalanced braces, parentheses or brackets, which in a widget tree ten
 *     levels deep is otherwise found by reading;
 *   - a widget class referenced but defined nowhere in lib/.
 *
 * Strings, comments and interpolation are skipped properly, because a naive
 * brace count reports every `${...}` as an error and then gets ignored.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");

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

const files = [...dartFiles(join(root, "lib"))];
console.log("\nSakina Dart sanity\n");
console.log(`${files.length} files under apps/mobile/lib`);
console.log("");

/**
 * Strip strings and comments so the bracket counter sees only code.
 *
 * Dart makes this fiddly: `'...'`, `"..."`, `'''...'''`, `r'...'`, and `${}`
 * interpolation that can itself contain strings. Interpolated expressions are
 * kept — their brackets are real and have to balance.
 */
function stripLiterals(source) {
  let out = "";
  let i = 0;

  while (i < source.length) {
    const rest = source.slice(i);

    if (rest.startsWith("//")) {
      const end = source.indexOf("\n", i);
      i = end === -1 ? source.length : end;
      continue;
    }
    if (rest.startsWith("/*")) {
      const end = source.indexOf("*/", i + 2);
      i = end === -1 ? source.length : end + 2;
      continue;
    }

    const raw = /^r(['"])/.exec(rest);
    const tripleMatch = /^r?('''|""")/.exec(rest);
    const singleMatch = /^r?(['"])/.exec(rest);

    if (tripleMatch) {
      const quote = tripleMatch[1];
      const start = i + tripleMatch[0].length;
      const end = source.indexOf(quote, start);
      i = end === -1 ? source.length : end + quote.length;
      out += '""';
      continue;
    }

    if (singleMatch) {
      const quote = singleMatch[1];
      const isRaw = Boolean(raw);
      let j = i + singleMatch[0].length;
      let literal = "";
      while (j < source.length) {
        const ch = source[j];
        if (!isRaw && ch === "\\") {
          j += 2;
          continue;
        }
        if (ch === quote) break;
        // Interpolation: keep the expression, drop the surrounding text. Its
        // braces are code and must be counted.
        if (!isRaw && ch === "$" && source[j + 1] === "{") {
          let depth = 1;
          let k = j + 2;
          while (k < source.length && depth > 0) {
            if (source[k] === "{") depth += 1;
            else if (source[k] === "}") depth -= 1;
            k += 1;
          }
          literal += " " + source.slice(j + 2, k - 1) + " ";
          j = k;
          continue;
        }
        j += 1;
      }
      out += '"' + literal + '"';
      i = j + 1;
      continue;
    }

    out += source[i];
    i += 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
const brokenImports = [];
const undeclaredPackages = [];
const unbalanced = [];

const pubspec = readFileSync(join(root, "pubspec.yaml"), "utf8");
const declared = new Set(
  [...pubspec.matchAll(/^\s{2}([a-z_0-9]+):/gm)].map((m) => m[1]),
);
// Provided by the SDK rather than listed as a dependency.
for (const built of ["flutter", "flutter_localizations", "flutter_test", "sky_engine"]) {
  declared.add(built);
}

const definedClasses = new Set();
const referencedWidgets = new Map();

for (const file of files) {
  const source = readFileSync(file, "utf8");
  const short = file.slice(root.length + 1);

  for (const [, target] of source.matchAll(/^import\s+'([^']+)'/gm)) {
    if (target.startsWith("dart:")) continue;
    if (target.startsWith("package:")) {
      const pkg = target.slice("package:".length).split("/")[0];
      if (!declared.has(pkg)) undeclaredPackages.push(`${short} -> ${pkg}`);
      continue;
    }
    const resolved = resolve(dirname(file), target);
    try {
      statSync(resolved);
    } catch {
      brokenImports.push(`${short} -> ${target}`);
    }
  }

  const code = stripLiterals(source);
  for (const [open, close, name] of [
    ["{", "}", "braces"],
    ["(", ")", "parentheses"],
    ["[", "]", "brackets"],
  ]) {
    let depth = 0;
    let bad = false;
    for (const ch of code) {
      if (ch === open) depth += 1;
      else if (ch === close) {
        depth -= 1;
        if (depth < 0) {
          bad = true;
          break;
        }
      }
    }
    if (bad || depth !== 0) unbalanced.push(`${short}: ${name} off by ${depth}`);
  }

  for (const [, name] of code.matchAll(/\bclass\s+([A-Z_][A-Za-z0-9_]*)/g)) {
    definedClasses.add(name);
  }
  for (const [, name] of code.matchAll(/\benum\s+([A-Z_][A-Za-z0-9_]*)/g)) {
    definedClasses.add(name);
  }
  // Our own widgets are the ones worth checking: anything named in this repo's
  // style that is constructed but defined nowhere is a rename that got missed.
  for (const [, name] of code.matchAll(/\b(Sakina[A-Za-z0-9_]*|Chorkhona[A-Za-z0-9_]*)\s*[.(]/g)) {
    if (!referencedWidgets.has(name)) referencedWidgets.set(name, short);
  }
}

check("every relative import resolves", brokenImports.length === 0,
  brokenImports.length ? brokenImports[0] : `${files.length} files`);

check("every package import is declared in pubspec", undeclaredPackages.length === 0,
  undeclaredPackages.length ? undeclaredPackages[0] : `${declared.size} packages`);

check("brackets balance in every file", unbalanced.length === 0,
  unbalanced.length ? unbalanced.slice(0, 3).join("; ") : "braces, parens and brackets");

const missingWidgets = [...referencedWidgets].filter(([name]) => !definedClasses.has(name));
check("every Sakina-named symbol used is defined", missingWidgets.length === 0,
  missingWidgets.length
    ? missingWidgets.map(([n, f]) => `${n} (${f})`).join(", ")
    : `${referencedWidgets.size} referenced`);

console.log(
  "\n  This is not a compiler. `dart analyze` catches strictly more, and none of",
);
console.log("  apps/mobile has been compiled — there is no Flutter SDK here.\n");

console.log(failures === 0 ? "All checks passed.\n" : `${failures} check(s) failed.\n`);
process.exit(failures === 0 ? 0 : 1);
