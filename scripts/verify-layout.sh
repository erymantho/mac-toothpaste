#!/usr/bin/env bash
# Checks the character → keystroke map that typing depends on. Builds the real KeyboardLayout
# for a fixed set of layouts, compares what it makes of a fixed set of characters with
# verify-layout.golden, and checks the rules from CLAUDE.md gotcha 4.
#
# It builds maps and reads them, nothing more: no event is posted, no permission is needed,
# and neither this Mac's keyboard layout nor its keyboard plays a part.
#
#   scripts/verify-layout.sh               check Sources/Toothpaste/Typing/KeyboardLayout.swift
#   scripts/verify-layout.sh <file>        check another copy of it instead
#   scripts/verify-layout.sh --update      record what the map is now as what it should be
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN="$ROOT/scripts/verify-layout.golden"
SOURCE="$ROOT/Sources/Toothpaste/Typing/KeyboardLayout.swift"
UPDATE=false
case "${1:-}" in
	--update) UPDATE=true ;;
	"") ;;
	*) SOURCE="$1" ;;
esac

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# No select-sdk.sh: like verify-watcher, this compiles AppKit and Carbon alone, which build
# on the default SDK. TargetProfile.swift is here so the maps are the ones the default
# profiles ask for, not a copy of their settings; KeyComposer.swift for the search's side.
swiftc -swift-version 5 -parse-as-library \
	-target "$(uname -m)-apple-macos14.0" \
	-o "$SCRATCH/verify-layout" \
	"$SOURCE" \
	"$ROOT/Sources/Toothpaste/Typing/TargetProfile.swift" \
	"$ROOT/Sources/Toothpaste/Typing/KeyComposer.swift" \
	"$ROOT/scripts/verify-layout.swift"

status=0
"$SCRATCH/verify-layout" "$SCRATCH/map" || status=1

if $UPDATE; then
	cp "$SCRATCH/map" "$GOLDEN"
	echo
	echo "recorded $(grep -vc '^#' "$GOLDEN") lines in scripts/verify-layout.golden; git diff shows what moved"
	exit "$status"
fi

echo
echo "=== against scripts/verify-layout.golden ==="
if [ ! -s "$GOLDEN" ]; then
	echo "FAIL  there is no golden file yet: run scripts/verify-layout.sh --update"
	exit 1
fi
if cmp -s <(grep -v '^#' "$GOLDEN") <(grep -v '^#' "$SCRATCH/map"); then
	echo "pass  every map is what the golden file expects"
	echo
	[ "$status" -eq 0 ] && echo "all passed" || echo "the map is as recorded, but a rule above failed"
	exit "$status"
fi

# Pairs each line with its counterpart by map and character, the first two fields, and says
# what that character's keys were and are. The `# data` lines say whether a layout's own bytes
# changed, which is the difference between a macOS update and a change in the code.
awk '
	function keys(line) { sub(/^[^ ]+ +[^ ]+ +[^ ]+ +/, "", line); return line }
	function change(map, text) {
		if (!(map in per)) maps[++mapCount] = map
		per[map]++
		lines[++changed] = text
	}
	FNR == NR {
		if ($1 == "#") {
			if ($2 == "data") wasData[$3] = $4 " " $7
			if ($2 == "macOS") { sub(/^# macOS /, ""); wasOS = $0 }
			next
		}
		was[$1 " " $2] = $0; order[++count] = $1 " " $2
		next
	}
	$1 == "#" {
		if ($2 == "data") nowData[$3] = $4 " " $7
		if ($2 == "macOS") { sub(/^# macOS /, ""); nowOS = $0 }
		next
	}
	{
		key = $1 " " $2; now[key] = 1
		if (!(key in was)) {
			change($1, sprintf("%-26s %-7s %s  new: %s", $1, $2, $3, keys($0)))
		} else if (was[key] != $0) {
			split(was[key], old, / +/)
			if ($2 == "reachable") change($1, sprintf("%-26s reachable  was %s, now %s", $1, old[3], $3))
			else change($1, sprintf("%-26s %-7s %s  was %s, now %s", $1, $2, $3, keys(was[key]), keys($0)))
		}
	}
	END {
		for (i = 1; i <= count; i++) if (!(order[i] in now)) {
			split(order[i], gone, " ")
			change(gone[1], sprintf("%-26s %-7s no longer in the map", gone[1], gone[2]))
		}
		summary = ""
		for (i = 1; i <= mapCount; i++) summary = summary (i > 1 ? ", " : "") maps[i] " " per[maps[i]]
		print "      " changed (changed == 1 ? " line differs: " : " lines differ: ") summary
		for (i = 1; i <= changed && i <= 20; i++) print "        " lines[i]
		if (changed > 20) print "        and " changed - 20 " more; --update, then git diff, shows them all"
		moved = ""; unread = ""
		for (i = 1; i <= mapCount; i++) {
			layout = maps[i]; sub(/\/.*/, "", layout)
			if (layout in seen) continue
			seen[layout] = 1
			if (!(layout in nowData)) unread = unread (unread == "" ? "" : ", ") layout
			else if (wasData[layout] != nowData[layout]) moved = moved (moved == "" ? "" : ", ") layout
		}
		if (unread != "") print "      Not read at all: " unread ". The first rule above says why."
		if (moved != "") {
			print "      The layout data changed for " moved ", written on macOS " wasOS ", now " nowOS "."
			print "      An update can change Apple'\''s layouts: if the code did not change, check the new"
			print "      lines are right, then record them with --update."
		} else if (unread == "") {
			print "      Each layout involved has the same bytes as when the golden file was written,"
			print "      so the change is in the code."
		}
	}
' "$GOLDEN" "$SCRATCH/map" > "$SCRATCH/report"

echo "FAIL  the map is not what the golden file expects"
cat "$SCRATCH/report"
exit 1
