#!/usr/bin/env bash
# Checks the clipboard watcher's capture rules — what is captured, what counts as a
# secret — by driving the real ClipboardWatcher against a private pasteboard.
#
# Unlike verify-capture.sh it touches nothing that is yours: not the clipboard you use,
# not the running app, not its history. It needs no permissions and no window.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# No select-sdk.sh here: the SDK it works around breaks SwiftUI's macros, and this compiles
# AppKit alone, which builds on the default SDK. One call site fewer to remove when the
# toolchain is fixed.
swiftc -swift-version 5 -parse-as-library \
	-target "$(uname -m)-apple-macos14.0" \
	-o "$SCRATCH/verify-watcher" \
	"$ROOT/Sources/Toothpaste/Clipboard/ClipboardWatcher.swift" \
	"$ROOT/Sources/Toothpaste/Clipboard/PasswordManagerExtensions.swift" \
	"$ROOT/scripts/verify-watcher.swift"

"$SCRATCH/verify-watcher"
