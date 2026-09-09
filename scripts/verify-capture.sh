#!/bin/bash
# Regression check for the clipboard capture and persistence rules.
# No permissions, no UI: drives the app with pbcopy and reads the file it writes.
#
# It needs a known-empty history to assert on, so it moves the real one aside and
# restores it via an EXIT trap — an earlier version simply deleted it, which destroyed
# a real history the first time it ran in anger.
set -u

DIR="$HOME/Library/Application Support/com.michaelsmith.toothpaste"
HIST="$DIR/history.json"
APP="$HOME/Applications/Toothpaste.app"

case "$HIST" in
	*/com.michaelsmith.toothpaste/history.json) ;;
	*) echo "refusing to touch unexpected history path: $HIST"; exit 1 ;;
esac

CONCEAL="$(mktemp -t tpconceal).swift"
cat > "$CONCEAL" <<'SWIFT'
import AppKit
// Mimics a password manager: text plus the community "concealed" convention type.
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString("supersecret-should-never-touch-disk", forType: .string)
pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
SWIFT

BACKUP="$(pbpaste)"
SAVED_HIST="$(mktemp -t tphist)"
if [ -f "$HIST" ]; then
	mv "$HIST" "$SAVED_HIST"
	echo "set aside your history"
fi

restore() {
	pkill -x Toothpaste 2>/dev/null
	sleep 0.5
	if [ -s "$SAVED_HIST" ]; then cp "$SAVED_HIST" "$HIST"; echo "restored your history"
	else rm -f "$HIST"; fi
	rm -f "$SAVED_HIST" "$CONCEAL"
	printf '%s' "$BACKUP" | pbcopy
	open "$APP"
}
trap restore EXIT

count() { python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$HIST" 2>/dev/null || echo 0; }
step() { printf '%s' "$1" | pbcopy; sleep 0.7; }

fail=0
check() { if [ "$1" = "0" ]; then echo "pass  $2"; else echo "FAIL  $2"; fail=1; fi; }

# --- captured items are session-only ---
pkill -x Toothpaste 2>/dev/null; sleep 0.5
open "$APP"; sleep 2

step 'first test entry'
step 'second entry 123'
step 'first test entry'          # dedupe: moves up rather than duplicating
step '     '                     # whitespace only: ignored
step $'multi\nline\ntext'
swift "$CONCEAL" >/dev/null 2>&1  # concealed: memory only
sleep 1.5

echo
echo "=== assertions ==="
[ "$(count)" = "0" ]
check $? "nothing unpinned is written to disk"

grep -q 'supersecret' "$HIST" 2>/dev/null; [ $? -ne 0 ]
check $? "concealed item stayed out of the file"

# --- pinned items outlive a restart ---
pkill -x Toothpaste 2>/dev/null; sleep 1
python3 - "$HIST" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
json.dump([{
    "id": str(uuid.uuid4()).upper(),
    "text": "pinned survivor",
    "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "pinned": True, "concealed": False,
}], open(sys.argv[1], "w"))
PY
open "$APP"; sleep 2
step 'something new after the restart'
sleep 1.5

grep -q 'pinned survivor' "$HIST" 2>/dev/null
check $? "a pinned entry survives a restart"

[ "$(count)" = "1" ]
check $? "the post-restart copy was not added to the file"

exit $fail
