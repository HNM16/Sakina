#!/bin/bash
#
# What a Claude Code on the web session needs before it can check anything.
#
# Registered as a SessionStart hook in .claude/settings.json. Two jobs:
#
#   1. the workspace's Node dependencies, so the JS checkers run;
#   2. the Flutter SDK, so `pnpm test:flutter` is a real analyzer rather than a
#      SKIPPED banner.
#
# The second one is the point. For most of this project's life there was no
# Flutter SDK in the web environment, so `apps/mobile` was checked only by
# dart-sanity.mjs — which is honest about not being a compiler. The first time a
# real `flutter analyze` ran against it, it found five compile errors and a
# dependency constraint that could never have resolved. That is the cost of
# writing Dart with no analyzer, and this script is how we stop paying it.
#
set -euo pipefail

# Local machines have their own toolchains, their own Flutter, and their own
# opinions about where it lives. Touching any of that would be rude.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Pinned, not "stable". A floating version means a Flutter release can turn a
# green tree red overnight for reasons nobody in this repo chose. Bump it
# deliberately: change the number, run `pnpm test:flutter`, fix what the new
# analyzer finds, and commit the two together.
FLUTTER_VERSION="3.47.2"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
BASE="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux"

# Never phone home. The documented opt-out command *sends an opt-out event*;
# this variable suppresses collection without any request at all, which is the
# only version of "off" worth the name.
export FLUTTER_SUPPRESS_ANALYTICS=true

echo "[sakina] session setup starting"

# ---------------------------------------------------------------- Flutter ---
# Idempotent on the version, not just on the path: a cached container from
# before a version bump has a Flutter, just not the one we asked for.
#
# The stamp is ours rather than Flutter's own bin/cache/flutter.version.json,
# for two reasons. Flutter moves its internal layout between releases — the
# top-level `version` file this first keyed on no longer exists, which made
# every session re-download 1.5GB and look idempotent while doing it. And a
# stamp we write last, after the install has actually succeeded, is the only
# thing that distinguishes a finished install from an interrupted one; a
# half-extracted tree with a plausible-looking version file inside it is worse
# than no tree at all.
STAMP="$FLUTTER_HOME/.sakina-flutter-version"
installed=""
if [ -x "$FLUTTER_HOME/bin/flutter" ] && [ -r "$STAMP" ]; then
  installed="$(cat "$STAMP" 2>/dev/null || true)"
fi

if [ "$installed" = "$FLUTTER_VERSION" ]; then
  echo "[sakina] flutter $FLUTTER_VERSION already present"
else
  if [ -n "$installed" ]; then
    echo "[sakina] replacing flutter $installed with $FLUTTER_VERSION"
    rm -rf "$FLUTTER_HOME"
  fi
  echo "[sakina] installing flutter $FLUTTER_VERSION (~1.5GB download, ~2.5GB on disk)"
  tmp="$(mktemp -d)"
  # --retry, because a single dropped connection should not cost the session
  # its analyzer.
  curl -fsSL --retry 3 --retry-delay 2 "$BASE/$ARCHIVE" -o "$tmp/flutter.tar.xz"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  tar -xJf "$tmp/flutter.tar.xz" -C "$(dirname "$FLUTTER_HOME")"
  rm -rf "$tmp"
  # Last, so an interrupted install leaves no stamp and the next session
  # reinstalls rather than trusting a partial tree.
  echo "$FLUTTER_VERSION" > "$STAMP"
fi

# The archive ships a git checkout, and the flutter tool shells out to git on
# every invocation. Git refuses to touch a repository whose owner differs from
# the current user, which in a container that switches users is every time —
# and it fails with exit 128 before Flutter can print anything useful.
git config --global --add safe.directory "$FLUTTER_HOME" 2>/dev/null || true

export PATH="$FLUTTER_HOME/bin:$PATH"

# Persist for the session: PATH so `flutter` and `dart` are callable, the two
# variables so nothing in the session re-derives them or re-enables telemetry.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\""
    echo "export FLUTTER_ROOT=\"$FLUTTER_HOME\""
    echo "export FLUTTER_SUPPRESS_ANALYTICS=true"
  } >> "$CLAUDE_ENV_FILE"
fi

flutter --version | grep -E '^Flutter' || true

# ------------------------------------------------------------------- deps ---
cd "$PROJECT_DIR"

# `install`, not `ci`/`--frozen-lockfile`: the container image is cached after
# this hook finishes, and install is the one that can reuse that cache.
echo "[sakina] pnpm install"
pnpm install --prefer-offline

# Resolves apps/mobile's packages into .dart_tool, which is gitignored and so
# never arrives with the clone. `flutter analyze` will not run without it.
echo "[sakina] flutter pub get"
(cd apps/mobile && flutter pub get >/dev/null)

echo "[sakina] ready — pnpm test:flutter now runs the real analyzer"
