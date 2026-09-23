#!/usr/bin/env bash
# Renders the app's windows offscreen under each appearance choice — Automatic, Light,
# Dark — and writes one PNG per window per choice to dist/appearances.
#
# Why this exists: the panel paints its own surfaces while its text uses the semantic
# colours, so a palette that is only ever looked at in one appearance can be badly wrong
# in the other with nothing to say so. That is exactly how 1.1.0 shipped unreadable in
# Light Mode. Checking it by switching the whole machine over is slow enough that it
# stops getting done.
#
# Nothing appears on screen and no focus is taken: the windows are never ordered front.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUT="$ROOT/dist/appearances"
OUT="${1:-$DEFAULT_OUT}"

# Start the default folder empty. A render that the renderer no longer produces would
# otherwise sit next to the current ones looking like a current defect — which happened
# with the first release-notes renders. Only the default folder: one passed as an argument
# might be somewhere else entirely, and this script deletes nothing it did not make.
# Same rule as bundle.sh uses for the bundle it deletes: refuse anything but the exact
# path expected, so an unset or mangled variable fails loudly instead of deleting
# something else.
if [ "$OUT" = "$DEFAULT_OUT" ]; then
	case "$DEFAULT_OUT" in
		/*/dist/appearances) rm -rf "$DEFAULT_OUT" ;;
		*) echo "refusing to clear unexpected path: $DEFAULT_OUT"; exit 1 ;;
	esac
fi

# HistoryStore saves on a timer and the renderer fills it with mock items, so both home
# variables point at a scratch directory — CFFIXED_USER_HOME as well as HOME, because
# Foundation consults it first. Without this the mock items land in the real
# history.json.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/home" "$OUT"

# See scripts/select-sdk.sh. It prints the two-dash form `swift build` wants, or nothing
# at all once the toolchain is healthy; swiftc spells the same flag with one dash.
SDK=$("$ROOT/scripts/select-sdk.sh")
SDK_FLAG=""
[ -n "$SDK" ] && SDK_FLAG="-sdk ${SDK#--sdk }"

# The real sources, minus the app's own entry point — the renderer brings its own.
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done \
	< <(find "$ROOT/Sources/Toothpaste" -name '*.swift' ! -name 'main.swift')

echo "compiling the renderer against ${#SOURCES[@]} source files"
# shellcheck disable=SC2086  # deliberate: expands to nothing, or to two arguments.
swiftc -swift-version 5 -parse-as-library $SDK_FLAG \
	-target "$(uname -m)-apple-macos14.0" \
	-o "$SCRATCH/render" "${SOURCES[@]}" "$ROOT/scripts/render-appearances.swift"

HOME="$SCRATCH/home" CFFIXED_USER_HOME="$SCRATCH/home" "$SCRATCH/render" "$OUT"
