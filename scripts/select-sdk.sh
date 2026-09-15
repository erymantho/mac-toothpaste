#!/usr/bin/env bash
# Prints the `--sdk <path>` argument the build needs, or nothing when the default SDK
# works.
#
# Why this exists: Command Line Tools 6.4 ships a macOS 27 SDK whose SwiftUI declares
# @State and friends as macros, but does *not* ship the SwiftUIMacros plugin that
# implements them. Every SwiftUI file then fails with
#
#   external macro implementation type 'SwiftUIMacros.StateMacro' could not be found
#
# Full Xcode has the plugin; Command Line Tools alone does not. Rather than require a
# 10 GB Xcode install for a 1.6 MB app, build against the newest SDK that does not need
# the plugin.
#
# Delete this once Command Line Tools ships the plugin, and drop the calls in
# Makefile and scripts/bundle.sh with it.
set -euo pipefail

PLUGINS="$(xcrun --find swift-frontend 2>/dev/null | xargs dirname)/../lib/swift/host/plugins"

# Plugin present: nothing to work around.
if [ -f "$PLUGINS/libSwiftUIMacros.dylib" ]; then
	exit 0
fi

DEFAULT_MAJOR="$(xcrun --show-sdk-version 2>/dev/null | cut -d. -f1)"
[ -n "$DEFAULT_MAJOR" ] || exit 0

# SDKs before macOS 27 declare @State the old way and need no plugin.
[ "$DEFAULT_MAJOR" -lt 27 ] && exit 0

SDK_DIR="$(xcrun --show-sdk-path | xargs dirname)"
for candidate in $(ls -1 "$SDK_DIR" | grep -oE 'MacOSX[0-9]+\.sdk' | sort -rV); do
	major="$(echo "$candidate" | grep -oE '[0-9]+')"
	if [ "$major" -lt 27 ]; then
		echo "--sdk $SDK_DIR/$candidate"
		exit 0
	fi
done

# Nothing older available. Let the build fail with Apple's own message, which says more
# than anything this script could invent.
exit 0
