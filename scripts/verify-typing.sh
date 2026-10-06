#!/usr/bin/env bash
# Checks what the typing engine would post — which keys, in which order, with which flags —
# for a few strings and the default profiles, without posting anything. The rules it holds
# the engine to are the ones RDP clients taught the hard way: CLAUDE.md gotchas 4 and 5.
#
# The harness replaces CoreGraphics' CGEvent with a class that records instead of posting
# (see scripts/verify-typing.swift). Before running it, this script checks that the binary
# does not link anything that creates or posts a real keyboard event, so a change that
# defeated the replacement fails here instead of typing into whatever has focus.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# No select-sdk.sh: like verify-watcher, this compiles AppKit and Carbon alone.
swiftc -swift-version 5 -parse-as-library \
	-target "$(uname -m)-apple-macos14.0" \
	-o "$SCRATCH/verify-typing" \
	"$ROOT/Sources/Toothpaste/Typing/TypingEngine.swift" \
	"$ROOT/Sources/Toothpaste/Typing/KeyboardLayout.swift" \
	"$ROOT/Sources/Toothpaste/Typing/TargetProfile.swift" \
	"$ROOT/scripts/verify-typing.swift"

# Read into a variable first: a failing nm inside the test would read as "nothing found".
UNDEFINED="$(nm -u "$SCRATCH/verify-typing")"
if REAL="$(printf '%s\n' "$UNDEFINED" | grep -E '^_CGEvent(Post|PostToPid|TapPostEvent|CreateKeyboardEvent)$')"; then
	echo "refusing to run: the harness links what posts real events:"
	printf '  %s\n' $REAL
	exit 1
fi

"$SCRATCH/verify-typing"
