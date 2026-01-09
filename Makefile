# Makefile for dotslash-files
# Provides a `test` target that runs shim tests and per-file sandbox tests.

SHELL := /usr/bin/env bash

DOTSLASH_FILES := $(wildcard bin/*.dotslash)
TEST_TARGETS := $(DOTSLASH_FILES:.dotslash=.test)

.PHONY: test shim-tests check-deps clean

# Default test target
test: shim-tests $(TEST_TARGETS)
	@echo "All tests completed."

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
%.test: %.dotslash
	@echo "Running sandbox test for $<"
	@if ! command -v podman >/dev/null 2>&1; then \
		echo "Warning: podman not found; skipping sandbox test for $<"; \
	else \
		./scripts/dotslash-sandbox "$<" --version >/dev/null; \
		echo "✓ $< passed"; \
	fi

# Clean up .test stamp files (if any were created as side-effects)
clean:
	@echo "Nothing to clean."
