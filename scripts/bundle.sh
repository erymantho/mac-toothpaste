#!/usr/bin/env bash
# Assembles dist/Toothpaste.app from the release build.
# There is no Xcode project here — only Command Line Tools are installed, so the
# bundle is put together by hand rather than by xcodebuild.
set -euo pipefail

APP_NAME="Toothpaste"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# A stable self-signed identity keeps the Accessibility grant across rebuilds.
# Ad-hoc signing ("-") pins the grant to the binary hash, so macOS revokes it
# every single build. See README.md.
SIGN_IDENTITY="${TOOTHPASTE_SIGN_IDENTITY:-Toothpaste Dev}"


# Deleting a bundle is the only destructive thing these scripts do. Rather than trust
# that every variable expanded correctly, refuse anything that is not an absolute path
# ending in Toothpaste.app. An empty or unexpected variable then fails loudly instead
# of removing something else.
remove_bundle() {
	local target="${1:-}"
	[ -n "$target" ] || { echo "refusing to remove an empty path"; exit 1; }
	case "$target" in
		/*/Toothpaste.app) ;;
		*) echo "refusing to remove unexpected path: $target"; exit 1 ;;
	esac
	[ -e "$target" ] || return 0
	rm -rf "$target"
}

swift build -c release --package-path "$ROOT"
BIN_PATH="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

remove_bundle "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/Toothpaste.icns" ] && cp "$ROOT/Resources/Toothpaste.icns" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Deliberately NOT `find-identity -v`: a self-signed root is untrusted, so -v filters
# it out entirely. codesign signs with it regardless, and the resulting designated
# requirement pins the *certificate* hash rather than the binary hash — which is the
# whole point, because that is what survives a rebuild and keeps the TCC grant.
MATCHES="$(security find-identity -p codesigning 2>/dev/null | grep "\"$SIGN_IDENTITY\"" || true)"
COUNT="$(printf '%s' "$MATCHES" | grep -c . || true)"
HASH="$(printf '%s\n' "$MATCHES" | head -1 | awk '{print $2}')"

if [ -n "$HASH" ]; then
	if [ "$COUNT" -gt 1 ]; then
		echo "WARNING: $COUNT certificates named '$SIGN_IDENTITY' exist."
		echo "         Using $HASH. Delete the spares in Keychain Access — if the"
		echo "         chosen one ever changes, the Accessibility grant resets."
	fi
	codesign --force --sign "$HASH" "$APP"
	echo "signed: $SIGN_IDENTITY ($HASH)"
else
	codesign --force --sign - "$APP"
	echo "WARNING: no certificate named '$SIGN_IDENTITY' — signed ad-hoc."
	echo "         macOS will revoke Accessibility permission on every rebuild."
	echo "         See README.md."
fi

echo "built: $APP"
