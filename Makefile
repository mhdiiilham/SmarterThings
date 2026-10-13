.PHONY: run stop app test

# Debug build, quit the running copy, open the new one.
run:
	./scripts/bundle.sh debug
	-pkill -x TVRemote
	open TVRemote.app

# Quit the running app (same as Quit in the remote's footer).
stop:
	-pkill -x TVRemote

# Optimized build for everyday use.
app:
	./scripts/bundle.sh release

test:
	swift test
