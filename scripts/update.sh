#!/usr/bin/env bash
# Pulls and reinstalls, after the app that asked for it has quit.
#
# Spawned detached by the running app, which then terminates: a bundle cannot replace
# itself while it is running, and `install.sh` deliberately quits the app before it
# copies. So the sequence is the app's last act, not something it supervises — it is
# gone by the second line of this script.
#
# There is no separate relaunch step. `make install` already ends with `open`, so a
# successful update brings the new version up by itself. A failure has to bring the
# *old* one back, because nothing else will.
#
# Deliberately not `set -e`: every failure here needs to leave a readable trace and
# restore a working app, which an early exit would skip.
set -uo pipefail

PID="${1:?usage: update.sh <pid-to-wait-for> <checkout>}"
ROOT="${2:?usage: update.sh <pid-to-wait-for> <checkout>}"

# A detached process started from an app bundle inherits almost no PATH. Everything
# used below lives in /usr/bin, but saying so beats finding out.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

SUPPORT="$HOME/Library/Application Support/com.michaelsmith.toothpaste"
APP="$HOME/Applications/Toothpaste.app"
LOG="$SUPPORT/update.log"
MARKER="$SUPPORT/update-failed"

mkdir -p "$SUPPORT"
# Truncated, not appended: only the last attempt is of any use, and an append-only log
# in Application Support is a file nobody ever prunes.
exec >"$LOG" 2>&1
echo "=== update started $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "checkout: $ROOT"

# Restores a usable app and leaves a one-line reason the app reads on next launch.
fail() {
	echo "FAILED: $1"
	printf '%s' "$1" >"$MARKER"
	open "$APP" 2>/dev/null || true
	exit 1
}

# kill -0 tests for existence without signalling. Ten seconds is far longer than a
# terminate takes; waiting forever would strand the update if the app hangs on quit.
echo "waiting for pid $PID to exit"
for _ in $(seq 1 100); do
	kill -0 "$PID" 2>/dev/null || break
	sleep 0.1
done
kill -0 "$PID" 2>/dev/null && fail "the app did not quit, so nothing was changed"

[ -d "$ROOT/.git" ] || fail "no git checkout at $ROOT"
[ -f "$ROOT/Makefile" ] || fail "no Makefile at $ROOT"
cd "$ROOT" || fail "cannot enter $ROOT"

# --ff-only on purpose: local commits or a dirty tree stop the update instead of being
# merged around. Someone who has been editing their own copy should be told, not
# quietly rebased.
echo "--- git pull ---"
git pull --ff-only || fail "git pull failed — local changes, or no network. See update.log."

echo "--- make install ---"
# `make install` builds and signs in full before install.sh touches ~/Applications, so
# a build failure here leaves the installed copy intact and this only has to relaunch it.
make install || fail "the build failed. See update.log."

rm -f "$MARKER"
echo "=== update finished $(date '+%Y-%m-%d %H:%M:%S') ==="
