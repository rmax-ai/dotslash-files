# Makefile for dotslash-files
# Provides a `test` target that runs shim tests and per-file sandbox tests.

SHELL := /usr/bin/env bash

DOTSLASH_FILES := $(wildcard bin/*.dotslash)
TEST_TARGETS := $(DOTSLASH_FILES:.dotslash=.test)

.PHONY: test shim-tests clean

# Default test target
test: shim-tests $(TEST_TARGETS)
	@echo "All tests completed."

# Run the existing shim tests
shim-tests:
	@./run_shim_tests.sh

# Pattern rule: each .test depends on the corresponding .dotslash file
# and runs dotslash-sandbox with --version to validate the manifest and binary.
%.test: %.dotslash
	@echo "Running sandbox test for $<"
	@./scripts/dotslash-sandbox "$<" --version >/dev/null
	@echo "✓ $< passed"

# Clean up .test stamp files (if any were created as side-effects)
clean:
	@echo "Nothing to clean."
