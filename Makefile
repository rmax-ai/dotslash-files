# Makefile for dotslash-files
# Provides a `test` target that runs shim tests and per-file sandbox tests.

SHELL := /usr/bin/env bash

# Disable parallel make to avoid interleaved outputo
# and podman errors due to concurrent container runs.
MAKEFLAGS += --no-print-directory -j1

DOTSLASH_FILES := $(wildcard bin/*.dotslash)
TEST_TARGETS := $(DOTSLASH_FILES:.dotslash=.test)

# Default platform for sandbox tests (can be overridden by environment)
TEST_SANDBOX_PLATFORM ?= linux/amd64

.PHONY: test shim-tests bin-tests install-tests check-deps clean

install-tests:
	@./tests/dotslash_install_test.sh



# Default test target
test: shim-tests bin-tests install-tests
	@echo "All tests completed."

# Run bin sandbox tests
bin-tests: $(TEST_TARGETS)
	@echo "All bin sandbox tests completed."

# Run the existing shim tests
shim-tests:
	@./run_shim_tests.sh

# Verify required dependencies are available (fails if missing)
check-deps:
	@command -v podman >/dev/null 2>&1 || { echo >&2 "Error: podman is required but not installed."; exit 1; }
	@echo "All required dependencies found."

# Pattern rule: each .test depends on the corresponding .dotslash file
# and runs dotslash-sandbox with --version to validate the manifest and binary.
# If `podman` is not available, the sandbox tests are skipped for each file.
# We capture the sandbox output (stdout+stderr) to avoid progress bars or carriage
# return artifacts from polluting the surrounding output and to enable clear
# success/failure messaging.
%.test: %.dotslash
	@echo "Running sandbox test for $<"
	@if ! command -v podman >/dev/null 2>&1; then \
		echo "Warning: podman not found; skipping sandbox test for $<"; \
	else \
		if [ -n "$(TEST_SANDBOX_PLATFORM)" ]; then \
			OUTPUT="$$(SANDBOX_PLATFORM=$(TEST_SANDBOX_PLATFORM) ./scripts/dotslash-sandbox "$<" --version 2>&1)"; \
		else \
			OUTPUT="$$(./scripts/dotslash-sandbox "$<" --version 2>&1)"; \
		fi; \
		STATUS=$$?; \
		if [ $$STATUS -eq 0 ]; then \
			echo "✓ $< passed"; \
		else \
			echo "✗ $< failed"; \
			echo "$$OUTPUT"; \
			exit $$STATUS; \
		fi; \
	fi

# Clean up .test stamp files (if any were created as side-effects)
clean:
	@echo "Nothing to clean."
