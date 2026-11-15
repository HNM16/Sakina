#!/usr/bin/env node
/**
 * The real analyzer, when there is one to run.
 *
 *   node apps/mobile/scripts/flutter-analyze.mjs
 *
 * `dart-sanity.mjs` next door says of itself, correctly, that it is not a
 * compiler: it checks that imports resolve, that packages are declared, that
 * brackets balance and that no Sakina-named symbol is used undefined. It cannot
 * see a wrong argument type, a renamed Flutter API, a missing `await`, or any
 * of the lints in `analysis_options.yaml`. For most of this project's life
 * there was no Flutter SDK in the environment and that was the best available.
 *
 * This runs `flutter analyze` instead, which catches strictly more. It does not
 * replace the sanity check — that one still runs everywhere, in about a second,
 * with no toolchain at all, and it is what stands between us and a broken tree
 * on a machine that has no SDK.
 *
 * ## Why this skips instead of failing
 *
 * A missing SDK is a fact about the machine, not a defect in the code, and a
 * suite that goes red for the former teaches people to ignore red. So a machine
 * without Flutter gets a loud SKIPPED and exit 0 — loud because the failure
 * mode to actually fear is a check that quietly never runs. In a Claude Code on
 * the web session `.claude/hooks/session-start.sh` installs the SDK before the
 * session starts, so there the skip should never appear.
 */
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const app = resolve(here, "..");

/**
 * Where a Flutter might be, in the order worth trusting.
 *
 * FLUTTER_ROOT first because someone who set it meant it; then PATH, the
 * ordinary case on a developer's machine; then the two places our own hook and
 * the common installers put it.
 */
function findFlutter() {
  const fromRoot = process.env.FLUTTER_ROOT
    ? join(process.env.FLUTTER_ROOT, "bin", "flutter")
    : null;
  if (fromRoot && existsSync(fromRoot)) return fromRoot;

  const onPath = spawnSync("which", ["flutter"], { encoding: "utf8" });
  if (onPath.status === 0 && onPath.stdout.trim()) return onPath.stdout.trim();

  for (const guess of [
    join(process.env.HOME ?? "", "flutter", "bin", "flutter"),
    "/opt/flutter/bin/flutter",
    "/usr/local/flutter/bin/flutter",
  ]) {
    if (guess && existsSync(guess)) return guess;
  }
  return null;
}

console.log("\nSakina Flutter analysis\n");

const flutter = findFlutter();
if (!flutter) {
  console.log("  ⊘ SKIPPED — no Flutter SDK on this machine.");
  console.log("");
  console.log("    `pnpm test:dart` still ran and still checks what it can, but");
  console.log("    it is not a compiler. To get the real thing:");
  console.log("");
  console.log("      https://flutter.dev/docs/get-started/install");
  console.log("");
  console.log("    Then re-run `pnpm test:flutter`. A Claude Code on the web");
  console.log("    session installs it automatically — see");
  console.log("    .claude/hooks/session-start.sh.");
  console.log("");
  process.exit(0);
}

const version = spawnSync(flutter, ["--version"], { encoding: "utf8" });
const line = (version.stdout ?? "").split("\n").find((l) => l.startsWith("Flutter"));
console.log(`  using ${flutter}`);
if (line) console.log(`  ${line.trim()}`);
console.log("");

// `analyze` refuses to run against unresolved packages, and the resolution
// lives in a gitignored directory — so a fresh clone needs this once. Cheap
// when it is already done, which is why it is not guarded on anything.
const pub = spawnSync(flutter, ["pub", "get"], {
  cwd: app,
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
});
if (pub.status !== 0) {
  console.log("  ✗ flutter pub get failed\n");
  console.log(pub.stdout ?? "");
  console.log(pub.stderr ?? "");
  process.exit(1);
}

const result = spawnSync(flutter, ["analyze", "--no-pub"], {
  cwd: app,
  encoding: "utf8",
});
const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();

if (result.status === 0) {
  console.log("  ✓ flutter analyze finds nothing");
  console.log("");
  console.log("All checks passed.\n");
  process.exit(0);
}

console.log("  ✗ flutter analyze found problems\n");
console.log(output);
console.log("");
process.exit(1);
