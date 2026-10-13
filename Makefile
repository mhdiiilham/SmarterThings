.PHONY: run stop app dmg test

VERSION ?= 1.0.0
export VERSION

# Debug build, quit the running copy, open the new one.
run:
	./scripts/bundle.sh debug
	-pkill -x SmarterThings
	open SmarterThings.app

# Quit the running app (same as Quit in the remote's footer).
stop:
	-pkill -x SmarterThings

# Optimized build for everyday use.
app:
	./scripts/bundle.sh release

# Drag-to-Applications disk image: build/SmarterThings-$(VERSION).dmg
dmg:
	./scripts/dmg.sh

test:
	swift test
