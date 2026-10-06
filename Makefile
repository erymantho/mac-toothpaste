APP := dist/Toothpaste.app

.PHONY: build app run cert install reset-permission verify verify-watcher verify-layout verify-typing appearances clean

# See scripts/select-sdk.sh: Command Line Tools 27 ships an SDK it cannot fully build
# against. Expands to nothing when the toolchain is healthy.
SDK := $(shell ./scripts/select-sdk.sh)

build:
	swift build $(SDK)

app:
	./scripts/bundle.sh

# `run` is deliberately an alias for `install`. Running dist/ directly means a second
# copy, at a path `make app` deletes on every build, and working out which one is live
# wastes more time than the install ever saves. (Both hold the Accessibility grant: it
# follows the signature, not the path.)
run: install

# One-time setup on a new machine.
cert:
	./scripts/create-cert.sh

install: app
	./scripts/install.sh

# Clears a stuck Accessibility grant for our bundle id only. Needed when the app was
# previously signed differently, so the entry in System Settings no longer matches it —
# the usual sign is the switch showing on while the app still reports it missing.
reset-permission:
	pkill -x Toothpaste 2>/dev/null || true
	tccutil reset Accessibility com.michaelsmith.toothpaste
	defaults delete com.michaelsmith.toothpaste panelOrigin 2>/dev/null || true
	@echo "Permission cleared. Run 'make install', then grant when prompted."

verify: app verify-watcher verify-layout verify-typing
	./scripts/verify-capture.sh

# What the clipboard watcher captures and what it counts as secret, against a private
# pasteboard. Unlike verify-capture.sh it touches nothing of yours, so it can run any time.
verify-watcher:
	./scripts/verify-watcher.sh

# The character → keystroke map typing depends on, for eight layouts every Mac has, against
# scripts/verify-layout.golden and the rules in gotcha 4. It posts no event, and this Mac's
# own layout and keyboard play no part. After a deliberate change, or a macOS update that
# changed a layout: scripts/verify-layout.sh --update, then read the git diff.
verify-layout:
	./scripts/verify-layout.sh

# What the typing engine would post — keys, order, flags — with every event recorded
# instead of posted. Gotchas 4 and 5, checked without a remote session or a permission.
verify-typing:
	./scripts/verify-typing.sh

# Both palettes, side by side, without switching the machine over. Writes PNGs to
# dist/appearances and never puts a window on screen.
appearances:
	./scripts/render-appearances.sh

clean:
	rm -rf .build dist
