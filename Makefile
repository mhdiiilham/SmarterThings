.PHONY: run app test

# Debug build, quit the running copy, open the new one.
run:
	./scripts/bundle.sh debug
	-pkill -x TVRemote
	open TVRemote.app

# Optimized build for everyday use.
app:
	./scripts/bundle.sh release

test:
	swift test
