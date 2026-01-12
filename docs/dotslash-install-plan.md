# Proposal: scripts/dotslash-install

Executive summary
-----------------
Provide a small, safe, user-friendly installer called `scripts/dotslash-install` that allows users to install .dotslash manifests from this repository's `bin/` directory into a local bin directory (default: $DOTSLASH_INSTALL_DIR (defaults to $XDG_BIN_HOME if set, otherwise $HOME/.dotslash/bin)). The installer will prefer local, opinionated behavior (no network operations), offer fast exact-match installs, and fall back to an interactive fuzzy selector when needed. It should be safe by default, non-destructive, and scriptable for CI or advanced users.

Motivation & goals
------------------
- Make it trivial for users to discover and install tools (manifests) from this repo.
- Provide a predictable, testable CLI with clear non-interactive and interactive modes.
- Avoid surprises: do not execute manifest contents and do not modify shell config files without clear opt-in.
- Support power users and scripted installs via flags (`--yes`, `--force`, `--dry-run`).

Non-goals
---------
- The installer will not fetch manifests from remote URLs (no network fetch by default).
- It will not interpret/execute manifests; it only copies and installs them as-is.

Personas & user stories
-----------------------
- New user: "I found a tool I want to try; I want a one-liner to install it and add it to my PATH."
- Scripter/CI: "I need to install manifests non-interactively in tests or ephemeral containers."
- Power user: "I want to quickly search and choose a manifest interactively with a preview pane."

Usability principles
--------------------
- Default to safe, ask before writing files or modifying shells.
- Make interactive flows fast and graceful with sensible fallbacks when optional tools are missing.
- Provide clear guidance when a tool is already present on the PATH.

High-level UX flow (concise)
----------------------------
1. Parse CLI args; show `--help` if missing/invalid.
2. Verify presence of `dotslash` in PATH; if missing, print an actionable suggestion and exit unless `--force-no-dotslash` is used.
3. Check for PATH collision: `command -v <query>`; warn and require confirmation to proceed unless `--yes`.
4. Locate candidates in `bin/`:
   - Fast exact-match using manifest "name" field if present.
   - Filename substring matches if no exact name match.
5. Depending on how many candidates are found (0, 1, or multiple), run the appropriate flow:
   - 0: No candidates found — show helpful suggestions (top N manifests or guidance on refining the query) and exit with status 2.
   - Single clear candidate: show manifest summary then confirm.
   - Multiple: if `fzf` available, present interactive list with a preview (jq or sed fallback). Otherwise present numbered list on stdout.
6. Prompt for or respect `--target` and create `$TARGET` (default: `$DOTSLASH_INSTALL_DIR` — resolves to `$XDG_BIN_HOME` if set, otherwise `$HOME/.dotslash/bin`).
7. Copy manifest to `$TARGET` and create a wrapper executable named after the tool that runs `dotslash <manifest> "$@"`.
8. Ensure installed bits are executable. If targets exist, prompt/abort/overwrite depending on flags.
9. If `$TARGET` is not on PATH, show shell-specific instructions and optionally append with explicit opt-in (`--append-path`).
10. Print success message and a simple smoke-check suggestion.

CLI: usage & flags (proposal)
-----------------------------
Usage: scripts/dotslash-install [OPTIONS] <query>

Options:
- -t, --target DIR       Install to DIR (default: $DOTSLASH_INSTALL_DIR — resolves to $XDG_BIN_HOME if set, otherwise $HOME/.dotslash/bin)
- -y, --yes              Accept all prompts (non-interactive)
- -f, --force            Overwrite existing installations
- --force-no-dotslash     Skip verifying that 'dotslash' is present in PATH (useful in minimal test environments)
- -n, --no-fzf           Disable fzf and use numbered selection fallback (useful in CI or when no TTY)
- --no-wrapper           Install only the manifest (do not create the executable wrapper)
- --append-path          Append export PATH line to the detected shell rc (explicit opt-in)
- --dry-run              Show what would happen and exit
- --verbose              Print diagnostic messages during execution
- -h, --help             Show usage

Examples:
- scripts/dotslash-install fzf
- scripts/dotslash-install -t $HOME/.local/bin ripgrep
- scripts/dotslash-install --append-path fzf
- scripts/dotslash-install --no-wrapper --dry-run helm
- scripts/dotslash-install --dry-run --target "$HOME/.local/bin" --verbose ripgrep

Design & implementation details
-------------------------------
Repo root discovery
- Use `git rev-parse --show-toplevel` when available for reliable repo root detection during development/tests. In release scripts, fall back to the script's path to find the bundled `bin/` directory (i.e., "$(dirname "$0")/.." style).

Default install directory resolution
- Resolution priority (first match wins):
  1. DOTSLASH_INSTALL_DIR environment variable, if set and non-empty.
  2. XDG_BIN_HOME, if set (support for de-facto user bin dirs).
  3. XDG_DATA_HOME/dotslash/bin, if XDG_DATA_HOME is set.
  4. $HOME/.dotslash/bin (fallback).

Example POSIX implementation:

# if [ -n "${DOTSLASH_INSTALL_DIR:-}" ]; then
#   TARGET="$DOTSLASH_INSTALL_DIR"
# elif [ -n "${XDG_BIN_HOME:-}" ]; then
#   TARGET="$XDG_BIN_HOME"
# elif [ -n "${XDG_DATA_HOME:-}" ]; then
#   TARGET="$XDG_DATA_HOME/dotslash/bin"
# else
#   TARGET="$HOME/.dotslash/bin"
# fi

- The script should ensure TARGET exists (mkdir -p) and is writable; if creation fails, print a clear error and exit with a non-zero status.

Manifest discovery & parsing
- Fast path: prefer exact match against the manifest `"name"` field.
  - If `jq` available: use `jq -r '.name // empty'` for reliable parsing.
  - If `jq` missing: use a conservative grep/sed/awk parser (avoid brittle regexes) and skip manifests that cannot be parsed.
- Filename scanning: match substring matches against filenames as a secondary fallback.
- Avoid any code execution from manifests; treat them as data-only.

Interactive selection
- Primary path: `fd -e dotslash bin | fzf --preview 'jq -C . {} 2>/dev/null || sed -n "1,200p" {}' --ansi --border --prompt="Select manifest> " --select-1 --exit-0`
- If `fzf` unavailable: list candidates numerically and read typed selection.
- Respect `--no-fzf` for non-interactive environments.

Install step & wrapper
- Copy the manifest file to `$TARGET/<basename>.dotslash`.
- Create a small, portable wrapper (preferred to a symlink). Example wrapper:

#!/usr/bin/env bash
# generated by dotslash-install (portable wrapper)
set -euo pipefail
# Resolve the wrapper directory reliably even when invoked via symlink
DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
exec dotslash "$DIR/<basename-of-manifest>.dotslash" "$@"

- Rationale: use a small wrapper rather than a symlink to avoid cross-filesystem and Windows symlink limitations. Create the wrapper with `install -m 0755` or `cp` + `chmod +x` to ensure correct permissions.

- Use `chmod +x` on the manifest and wrapper to ensure executability.
- `--no-wrapper` skips wrapper creation; this is useful when a user prefers to call `dotslash` directly.

PATH detection & shell integration
- Check whether `$TARGET` is exactly one of the path entries. Use `tr ':' '\n'` and compare.
- Detect the user's shell via `$SHELL` and recommend an rc file to update (e.g., zsh -> ~/.zshrc, bash -> ~/.bashrc). For macOS, prefer ~/.bash_profile if present.
- Only append to rc files when `--append-path` is explicitly passed and the user confirms.
- Use an idempotent append that checks if the export line already exists before writing.

Errors, exit codes & logging
- Exit codes:
  0: success
  1: usage / invalid args
  2: candidate not found
  3: missing dependency (e.g., dotslash required and not found)
  4: user aborted
  >10: internal unexpected errors
- Provide `--dry-run` and `--verbose` to aid testing and debugging.

Edge cases & safety
- If no candidates found, show helpful suggestions: top N manifests or guidance on refining the query.
- If a manifest lacks a `name` field or is otherwise malformed, skip it and warn.
- If a command of the same name exists on PATH, warn and require explicit confirmation to proceed.
- Do not follow or resolve symlinks when reading manifests in the repo; operate on repository files only.

Testing strategy
----------------
Add tests at `tests/dotslash_install_test.sh` exercising:
1. Exact match: script installs manifest to a temporary target and creates a wrapper that correctly execs dotslash.
2. Fuzzy selection: simulate selection by invoking with `--no-fzf` and verifying chosen candidate via stdout prompts.
3. Missing `dotslash` behavior: when `dotslash` is absent, assert the script exits non-zero and prints actionable hints.
4. PATH instruction: target not on PATH should result in printed `export PATH=...` instruction; `--append-path` should modify a temp rc file in tests.
5. Overwrite with `--force`: existing installation replaced when `--force` used.
6. Dry-run: nothing is written when `--dry-run` is used; output shows intended actions.

Testing notes:
- Use temporary directories and modify the environment (PATH, SHELL) for isolation.
- Make tests runnable via `make shim-tests` or `make install-tests` (add a Makefile target).

Minimal Makefile target suggestion:

install-tests:
	./tests/dotslash_install_test.sh

- Ensure tests can run in environments without fzf by default and can opt-in to running fzf-specific tests when the tool is available.

Acceptance criteria
-------------------
- Script implements exact-match install and wrapper creation.
- Interactive fuzzy selection works when `fzf` is installed; graceful fallback works without it.
- Tests covering primary flows exist and pass in CI.
- Script documents usage and flags in README or man-style help output.

Security & privacy considerations
--------------------------------
- The installer will never execute code from manifests. It only copies files and creates wrappers.
- When appending to shell rc files, make minimal, clearly annotated edits and request explicit user consent.
- Avoid storing sensitive data or secrets; treat manifest contents as public repository data.

Timeline & milestones (proposal)
--------------------------------
1. Week 1: scaffold script, implement argument parsing, repo root discovery, basic exact-match install, minimal tests (temp dir) — open draft PR.
2. Week 2: add fuzzy selection (fzf preview), manifest parsing fallbacks, wrapper creation, PATH detection and guidance, expand tests.
3. Week 3: polish UX, add `--append-path` functionality, comprehensive test coverage, documentation and README blurb, address review feedback.

Files to add / modify
---------------------
- scripts/dotslash-install (executable script)
- tests/dotslash_install_test.sh
- docs/dotslash-install-plan.md (this file)
- README.md (usage blurb - optional)
- Makefile (test target - optional)

Implementation checklist & pseudocode
-----------------------------------
- CLI parsing: implement getopt/getopts parsing for flags: --target/-t, --yes/-y, --force/-f, --force-no-dotslash, --no-fzf/-n, --no-wrapper, --append-path, --dry-run, --verbose, --help/-h.
- Repo root detection: prefer `git rev-parse --show-toplevel` when available; otherwise use the script's path.
- Manifest discovery: scan `bin/` for `*.dotslash`, parse `name` with `jq` or a conservative grep/sed fallback, and build a mapping name -> file path.
- Candidate selection: exact match by name; filename substring fallback; interactive selection via `fzf` (with preview) or numeric prompt fallback.
- Install step:
  - Resolve TARGET (DOTSLASH_INSTALL_DIR > XDG_BIN_HOME > XDG_DATA_HOME/dotslash/bin > $HOME/.dotslash/bin), `mkdir -p`, ensure writable.
  - Copy manifest to `$TARGET/<basename>.dotslash` (use `cp -p` to preserve mode).
  - Create wrapper (unless `--no-wrapper`) at `$TARGET/<toolname>` with content (see example below) and `chmod +x` both files.
  - If files exist, follow `--yes` and `--force` semantics.
- PATH detection: check PATH entries; if not present and `--append-path` is requested and confirmed, append an idempotent export line to the user's shell rc file with a marker comment.
- Dry-run & verbose: honor `--dry-run` to print actions only; `--verbose` prints diagnostic steps.
- Exit codes: follow the documented mapping (0 success, 1 usage, 2 candidate not found, 3 missing dependency, 4 user aborted).

Small scaffold (pseudo-shell):

#!/usr/bin/env bash
set -euo pipefail
# parse args
# locate repo root
# discover manifests
# select candidate
# perform dry-run or install
# print success / instructions

Testing notes (expanded)
-------------------------
- `tests/dotslash_install_test.sh` should be a POSIX shell script that:
  - Uses `mktemp -d` for isolated temp dirs and cleans up on exit.
  - Exports `DOTSLASH_INSTALL_DIR` to a temp dir for the install target.
  - Creates a fake `dotslash` shim in PATH when testing wrapper execution.
  - Tests should assert:
    - Exact-match installs create manifest + wrapper and wrapper execs `dotslash` with correct args.
    - Fuzzy selection and numeric fallback work as intended.
    - Missing `dotslash` behavior exits non-zero and prints actionable hints (unless `--force-no-dotslash`).
    - PATH instructions are printed when target not on PATH; `--append-path` modifies a temp rc file.
    - `--force` overwrites existing installation; `--dry-run` performs no writes.
- Add `install-tests` Makefile target that runs the script and integrates with `make shim-tests` when appropriate (see minimal example below).

Minimal Makefile target suggestion:

install-tests:
	./tests/dotslash_install_test.sh

- Ensure tests are resilient when `fzf` or `jq` are absent; skip or simulate these tools where needed.

Decisions
---------
- Install dir resolution: DOTSLASH_INSTALL_DIR > XDG_BIN_HOME > XDG_DATA_HOME/dotslash/bin > $HOME/.dotslash/bin (see the "Default install directory resolution" section and example pseudocode).
- Verification of 'dotslash' presence: the script will verify that `dotslash` exists on PATH by default and exit with an actionable hint; use `--force-no-dotslash` to skip this check in constrained test environments.
- Interactive defaults: `fzf` is optional. When available it provides an enhanced interactive selection; otherwise the script falls back to a numeric prompt. Respect `--no-fzf` to force the fallback.
- Batch installs and strict manifest validation: deferred. Initial implementation will focus on single-manifest installs and will warn and skip malformed manifests rather than failing hard.

Open questions
--------------
- Are there additional platform-specific edge cases to handle beyond the macOS `~/.bash_profile` preference? Defer to implementation and testing for any platform-specific tweaks.
- Should we provide a convenience command for installing multiple manifests in one invocation (e.g., `dotslash-install fzf rg`) or add that as an opt-in enhancement later? (deferred)

Next steps
----------
- Review this proposal and converge on CLI flags and default behavior.
- I can implement the scaffold (argument parsing + exact-match install) and tests, open a draft PR for review, and iterate on the interactive pieces (`fzf`/preview) once basic tests pass.

If you'd like, I will scaffold the script and tests now and open a draft PR for feedback. Specify whether you prefer the default install dir to be $DOTSLASH_INSTALL_DIR (defaults to $XDG_BIN_HOME if set, otherwise $HOME/.dotslash/bin), or want XDG-style defaults by default.