#!/usr/bin/env node
/**
 * The widget tests — the cheapest way to actually *run* this app.
 *
 *   node apps/mobile/scripts/flutter-test.mjs
 *
 * `flutter test` needs no device, no emulator and no platform SDK: it builds
 * the widgets, lays them out and dispatches gestures in a headless harness.
 * That matters here more than it does on most projects, because for a long
 * time nothing in `apps/mobile` had ever been executed at all.
 *
 * It earns its place against the two checks either side of it. `test:dart`
 * parses, `test:flutter` type-checks — and the unread badge passed both while
 * rendering as a firuza bar straight across every chat name, because no
 * checker that never lays a widget out can see a `Container` accept the full
 * width it was offered. `test/widget_test.dart` now pins that.
 *
 * Skips loudly with exit 0 where there is no SDK, for the same reason
 * flutter-analyze.mjs does: a missing toolchain is a fact about the machine,
 * not a defect in the code.
 */
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const app = resolve(here, "..");

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

console.log("\nSakina widget tests\n");

const flutter = findFlutter();
if (!flutter) {
  console.log("  ⊘ SKIPPED — no Flutter SDK on this machine.");
  console.log("");
  console.log("    These are the only checks that actually run the app's");
  console.log("    widgets. To get them: https://flutter.dev/docs/get-started/install");
  console.log("    A Claude Code on the web session installs Flutter itself —");
  console.log("    see .claude/hooks/session-start.sh.");
  console.log("");
  process.exit(0);
}

const result = spawnSync(flutter, ["test", "--reporter", "compact"], {
  cwd: app,
  encoding: "utf8",
});
const output = `${result.stdout ?? ""}${result.stderr ?? ""}`
  .split("\n")
  // The compact reporter redraws its progress line with carriage returns, so
  // a naive capture prints every intermediate state on one enormous line.
  // Only the text after the last \r is what the terminal actually showed.
  .map((line) => line.slice(line.lastIndexOf("\r") + 1))
  // The root warning is unavoidable in a container and says nothing about us.
  .filter((l) => l.trim() && !/Woah!|superuser privileges|^\s*\/\s*$|^📎$/.test(l))
  .join("\n")
  .trim();

console.log(output);
console.log("");

if (result.status === 0) {
  console.log("All checks passed.\n");
  process.exit(0);
}
process.exit(1);
