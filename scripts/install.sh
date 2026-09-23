#!/usr/bin/env bash
# Installs the built app to ~/Applications and runs it from there.
#
# Why not just run dist/Toothpaste.app:
#
# NOT for the Accessibility grant — that follows the code signature, and since both
# copies carry the same bundle id and certificate, TCC treats them as the same app
# regardless of path. Verified with `codesign --verify -R`.
#
# The real reasons are smaller but real: launch-at-login registers a *path*, and
# `make app` deletes that bundle on every build; two copies both register with
# LaunchServices and show up twice in Launchpad; and the project folder is
# Nextcloud-synced, so the app would depend on a sync client having done its work.
set -euo pipefail

APP_NAME="Toothpaste"
BUNDLE_ID="com.michaelsmith.toothpaste"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/dist/$APP_NAME.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME.app"

[ -d "$SRC" ] || { echo "error: $SRC does not exist — run 'make app' first"; exit 1; }

echo "quitting any running instance"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

mkdir -p "$DEST_DIR"

# Update in place rather than delete-and-recreate. Removing the very bundle the
# Accessibility grant points at is how the permission got lost in the first place;
# ditto overwrites the contents while the .app directory itself keeps existing.
# ditto (not cp) because it preserves the code signature and extended attributes.
ditto "$SRC" "$DEST"

echo "verifying the installed copy"
codesign --verify --strict "$DEST" && echo "  signature valid"
codesign -d -r- "$DEST" 2>&1 | grep designated | sed 's/^/  /'

# Two entries for the same app in Launchpad — one of them the unpermissioned build
# output — is only confusing. Unregister the source copy.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -u "$SRC" 2>/dev/null || true

open "$DEST"
echo
echo "installed and launched: $DEST"
echo "Grant Accessibility to this copy if you have not already."
