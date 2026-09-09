APP := dist/Toothpaste.app

.PHONY: build app run cert install reset-permission verify clean

build:
	swift build

app:
	./scripts/bundle.sh

# `run` is deliberately an alias for `install`. Running dist/ directly means a second
# copy without the Accessibility grant, and working out which one is live wastes more
# time than the install ever saves.
run: install

# One-time setup on a new machine.
cert:
	./scripts/create-cert.sh

install: app
	./scripts/install.sh

# Clears a stuck Accessibility grant for our bundle id only. Needed when the app was
# previously signed differently, or when the granted copy was deleted underneath TCC.
reset-permission:
	pkill -x Toothpaste 2>/dev/null || true
	tccutil reset Accessibility com.michaelsmith.toothpaste
	defaults delete com.michaelsmith.toothpaste panelOrigin 2>/dev/null || true
	@echo "Permission cleared. Run 'make install', then grant when prompted."

verify: app
	./scripts/verify-capture.sh

clean:
	rm -rf .build dist
