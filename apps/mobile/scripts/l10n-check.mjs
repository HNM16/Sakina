#!/usr/bin/env node
/**
 * Is every user-facing string actually in all three languages?
 *
 *   node apps/mobile/scripts/l10n-check.mjs
 *
 * A missing key does not crash — `t()` falls back to Russian — which is what
 * makes this worth automating. An untranslated Tajik string looks completely
 * normal to anyone reading the app in Russian, and completely broken to the
 * audience the app exists for.
 *
 * It also checks two things that are specific to this project:
 *
 *   - the six Tajik Cyrillic characters (ғ ӣ қ ӯ ҳ ҷ) appear in real strings,
 *     so the font choice is exercised by the UI rather than only by a doc;
 *   - no string is so much longer in Tajik than in Russian that a button sized
 *     against Russian would clip it. Tajik runs about a third longer as a rule;
 *     past roughly double, the string wants rewording rather than a wider
 *     button.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "../lib/src/l10n.dart"), "utf8");

let failures = 0;
function check(label, condition, detail = "") {
  if (!condition) failures += 1;
  console.log(`  ${condition ? "✓" : "✗"} ${label}${detail ? ` — ${detail}` : ""}`);
}

const body = source.slice(
  source.indexOf("static const _strings"),
  source.indexOf("String t(String key)"),
);

const LANGS = ["ru", "tg", "en"];
const entries = [...body.matchAll(/'([a-z_0-9]+)':\s*\{([^}]*)\}/gs)];

console.log("\nSakina localisation\n");
console.log(`${entries.length} strings, ${LANGS.length} languages`);
console.log("");

const missing = [];
const duplicates = [];
const values = new Map();

for (const [, key, langBlock] of entries) {
  const perLang = {};
  for (const lang of LANGS) {
    // Single- or double-quoted; Dart allows both and the copy uses both,
    // because an apostrophe in "Couldn't" has to live somewhere.
    const match =
      langBlock.match(new RegExp(`'${lang}':\\s*'((?:[^'\\\\]|\\\\.)*)'`)) ??
      langBlock.match(new RegExp(`'${lang}':\\s*"((?:[^"\\\\]|\\\\.)*)"`));
    if (!match) missing.push(`${key} is missing ${lang}`);
    else perLang[lang] = match[1];
  }
  if (values.has(key)) duplicates.push(key);
  values.set(key, perLang);
}

// Dart will not accept two equal keys in a const map — it is a compile error,
// not a warning. This check exists because JavaScript *will*: `values` is a
// Map, so before this the second `new_chat` quietly replaced the first and the
// tree looked healthy right up until something tried to compile it. That is
// the failure this whole script is supposed to prevent, so it is worth the
// four lines even now that `pnpm test:flutter` would also catch it — that one
// needs an SDK, and this one runs anywhere in a second.
check("no key is defined twice", duplicates.length === 0,
  duplicates.length ? `duplicated: ${duplicates.join(", ")}` : `${values.size} distinct`);

check("every string exists in all three languages", missing.length === 0,
  missing.length ? `${missing.length} gaps, first: ${missing[0]}` : `${entries.length} complete`);

// The six characters that decide the font. If none of the UI copy contains
// them, the font requirement in docs/BRAND.md is untested by the product.
const tajik = [...values.values()].map((v) => v.tg ?? "").join("");
const SPECIAL = [..."ғӣқӯҳҷ"];
const absent = SPECIAL.filter((c) => !tajik.toLowerCase().includes(c));
check("the six Tajik characters appear in real UI copy", absent.length === 0,
  absent.length ? `never used: ${absent.join(" ")}` : SPECIAL.join(" "));

// Length. Tajik is reliably the longest of the three and is what buttons get
// sized against; this catches the case where it is longer than that assumption.
const overlong = [];
let worstRatio = 0;
let worstKey = "";
for (const [key, v] of values) {
  if (!v.tg || !v.ru) continue;
  const ratio = v.tg.length / Math.max(v.ru.length, 1);
  if (ratio > worstRatio) {
    worstRatio = ratio;
    worstKey = key;
  }
  if (v.tg.length > v.ru.length * 2 && v.tg.length > 24) {
    overlong.push(`${key}: ${v.tg.length} vs ${v.ru.length}`);
  }
}
check("no Tajik string is more than twice its Russian length", overlong.length === 0,
  overlong.length ? overlong[0] : `worst is ${worstKey} at ${worstRatio.toFixed(2)}x`);

// Russian is the default and the fallback; an empty one is a blank label.
const empty = [...values.entries()].filter(([, v]) => (v.ru ?? "").trim() === "");
check("no Russian string is empty", empty.length === 0,
  empty.length ? empty[0][0] : "all present");

// The declared order is the policy — Flutter falls through to the first entry.
const order = source.match(/supportedLocales\s*=\s*\[([^\]]*)\]/s)?.[1] ?? "";
const declared = [...order.matchAll(/Locale\('(\w+)'\)/g)].map((m) => m[1]);
check("Russian is the first supported locale", declared[0] === "ru",
  declared.join(" > "));
check("Tajik is second", declared[1] === "tg", declared.join(" > "));

// ---------------------------------------------------------------------------
// Every key the UI asks for must exist.
//
// This is the check that earns its keep. `t()` returns the KEY ITSELF when it
// misses, so a typo ships as a button labelled "chanel_name" — visible to
// nobody who tests in the language they wrote it in, and visible to everyone
// else.
// ---------------------------------------------------------------------------
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
 * Every string literal that reaches a `t(...)` call.
 *
 * A regex for `t('key')` alone misses the common shape in this codebase —
 * `t(isChannel ? 'channel_name' : 'group_name')` — which is exactly where a
 * typo hides, because only one branch is ever exercised by whoever wrote it.
 * So the argument is scanned with balanced parentheses instead.
 */
function keysUsedIn(text) {
  const keys = [];
  const call = /\bt\(/g;
  let match;
  while ((match = call.exec(text)) !== null) {
    let depth = 1;
    let i = match.index + match[0].length;
    const start = i;
    while (i < text.length && depth > 0) {
      const ch = text[i];
      if (ch === "(") depth += 1;
      else if (ch === ")") depth -= 1;
      i += 1;
    }
    const argument = text.slice(start, i - 1);
    // Only literals — a variable holding a key cannot be checked statically,
    // and there are none in this codebase today.
    for (const [, key] of argument.matchAll(/'([a-z][a-z_0-9]*)'/g)) keys.push(key);
  }
  return keys;
}

const known = new Set(values.keys());
const unknown = new Map();
const usedKeys = new Set();

for (const file of dartFiles(join(here, "../lib"))) {
  const shortName = file.split("/apps/mobile/")[1];
  for (const key of keysUsedIn(readFileSync(file, "utf8"))) {
    usedKeys.add(key);
    if (!known.has(key)) unknown.set(key, shortName);
  }
}

check("every key the UI asks for is defined", unknown.size === 0,
  unknown.size
    ? [...unknown].slice(0, 4).map(([k, f]) => `${k} (${f})`).join(", ")
    : `${usedKeys.size} of ${known.size} keys reached from the UI`);

// Not a failure: a string may land just ahead of the screen that uses it.
const unused = [...known].filter((k) => !usedKeys.has(k));
if (unused.length) {
  console.log(`  · ${unused.length} defined but unused: ${unused.slice(0, 8).join(", ")}`);
}

console.log(failures === 0 ? "\nAll checks passed.\n" : `\n${failures} check(s) failed.\n`);
process.exit(failures === 0 ? 0 : 1);
