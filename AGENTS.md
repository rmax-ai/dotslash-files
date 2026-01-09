# AGENTS.md

Purpose
-------
Provide guidance for automated agents (bots/CI) and maintainers about which tests to run when specific areas of this repository change.

Rules
-----
- When a commit/PR modifies any files under `scripts/` (e.g. edits to `scripts/dotslash-shim`), run:

    make shim-tests

  Rationale: `make shim-tests` runs the shim test suite (via `./run_shim_tests.sh`) which validates behavior of the shim(s).

- When a commit/PR adds new files under `bin/` (new `.dotslash` manifests or binaries), run:

    make bin-tests

  Rationale: `make bin-tests` runs the per-file sandbox tests (Makefile pattern targets) which exercise `scripts/dotslash-sandbox` and validate manifests/binaries.

- If both areas are changed, run both targets (order doesn't matter):

    make shim-tests && make bin-tests

Notes / Implementation hints
---------------------------
- `make test` is a convenience target that runs both (`shim-tests` and `bin-tests`).
- `make bin-tests` will skip sandbox tests if `podman` is not available (the Makefile emits a warning in that case).
- Example agent snippet to detect and run tests:

    CHANGED_FILES=$(git diff --name-only origin/main...HEAD || true)
    if echo "$CHANGED_FILES" | grep -q '^scripts/'; then
      make shim-tests
    fi
    if echo "$CHANGED_FILES" | grep -q '^bin/'; then
      make bin-tests
    fi

Where to look
-------------
- Shim tests: `run_shim_tests.sh` and `tests/dotslash_shim_test.sh`
- Bin sandbox tests: `Makefile` (pattern rule `%.test: %.dotslash`) and `scripts/dotslash-sandbox`

This file is intended to be machine-readable guidance for repository automation and also a quick reference for maintainers.