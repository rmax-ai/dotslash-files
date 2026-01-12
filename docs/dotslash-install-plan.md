# Proposal: scripts/dotslash-install

Executive summary
-----------------

Status: Ready for implementation. This document defines the desired behavior, UX, and acceptance criteria for scripts/dotslash-install and is ready for implementation.
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

Help & sample output
--------------------
Help output (example):

$ scripts/dotslash-install -h
Usage: scripts/dotslash-install [OPTIONS] <query>

Options:
  -t, --target DIR       Install to DIR (default: $DOTSLASH_INSTALL_DIR — resolves to $XDG_BIN_HOME if set, otherwise $HOME/.dotslash/bin)
  -y, --yes              Accept all prompts (non-interactive)
  -f, --force            Overwrite existing installations
  --force-no-dotslash    Skip verifying that 'dotslash' is present in PATH
  -n, --no-fzf           Disable fzf and use numbered selection fallback
  --no-wrapper           Install only the manifest (do not create the executable wrapper)
  --append-path          Append export PATH line to the detected shell rc (explicit opt-in)
  --dry-run              Show what would happen and exit
  --verbose              Print diagnostic messages during execution
  -h, --help             Show usage

Success (example):

Installed "fzf" to $TARGET
- manifest: $TARGET/fzf.dotslash
- wrapper:  $TARGET/fzf

If $TARGET is not on your PATH, add it:
  export PATH="$TARGET:$PATH"

Run 'fzf' to verify the installation.

Notes:
- Exit codes follow the documented mapping (0 success, 1 usage error, 2 candidate not found, 3 missing dependency, 4 user aborted).

Failure & error examples (example outputs)
-----------------------------------------
Missing dependency (dotslash not found): exit code 3

$ scripts/dotslash-install fzf
Error: 'dotslash' not found on PATH.
Hint: Install the 'dotslash' runner or use --force-no-dotslash in constrained environments.
Exit status: 3

Path collision (existing command on PATH):

$ scripts/dotslash-install ripgrep
Warning: a command named 'rg' exists on PATH at /usr/local/bin/rg
Install 'ripgrep' anyway? (y/N)  [use --yes to accept]
If user aborts: exit status 4

No candidates found (exit code 2):

$ scripts/dotslash-install unknown-tool
No manifests in 'bin/' match 'unknown-tool'. Try a different query; see top suggestions:
  - fzf
  - ripgrep
Exit status: 2

Append PATH success example:
If $TARGET not on PATH and --append-path is used:
Wrote 'export PATH="$TARGET:$PATH"' to ~/.zshrc (# added by dotslash-install)

Dry-run example (no files written):

$ scripts/dotslash-install --dry-run demo-tool
Would install "demo-tool" to $TARGET
- manifest: would copy bin/demo-tool.dotslash -> $TARGET/demo-tool.dotslash
- wrapper: would create $TARGET/demo-tool
No files were written.

Verbose output example:

$ scripts/dotslash-install --dry-run --verbose demo-tool
Resolving TARGET...
TARGET resolved to: $TARGET
Searching bin/ for manifests...
Found candidate: bin/demo-tool.dotslash (name: demo-tool)
Target directory does not exist; would run: mkdir -p "$TARGET"
Would copy: bin/demo-tool.dotslash -> $TARGET/demo-tool.dotslash
Would create wrapper: $TARGET/demo-tool
No files were written.

Smoke check:
After a successful install, verify by running:
$ demo-tool --version
or
$ $TARGET/demo-tool --version

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

- The script should ensure TARGET exists (mkdir -p) and is writable; if creation fails, print a clear error and exit with a non-zero status. Example error:

Error: could not create target directory '$TARGET': Permission denied
Exit status: >10

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
- Check whether `$TARGET` is exactly one of the path entries. Use `tr ':' '\n'` and compare. Example:

# simple PATH detection snippet (POSIX)
# if echo "$PATH" | tr ':' '\n' | grep -xq "$TARGET"; then
#   echo "on PATH"
# else
#   echo "not on PATH"
# fi

- Detect the user's shell via `$SHELL` and recommend an rc file to update (e.g., zsh -> ~/.zshrc, bash -> ~/.bashrc). For macOS, prefer ~/.bash_profile if present.
- Only append to rc files when `--append-path` is explicitly passed and the user confirms.
- Use an idempotent append that checks if the export line already exists before writing. Example idempotent append:

# if ! grep -Fq "# added by dotslash-install" "$RC"; then
#   printf "\n# added by dotslash-install\nexport PATH=\"$TARGET:$PATH\"\n" >> "$RC"
# fi

Errors, exit codes & logging
- Exit codes:
  0: success
  1: usage / invalid args
  2: candidate not found
  3: missing dependency (e.g., dotslash required and not found)
  4: user aborted
  >10: internal unexpected errors
- Provide `--dry-run` and `--verbose` to aid testing and debugging.

Edge cases & safety (detailed policies)
- No candidates found: show helpful suggestions (top N manifests) and exit with code 2. Provide guidance on refining queries and suggest closest matches.
- Duplicate names: if multiple manifests share the same `.name` value, treat them as distinct candidates and present an interactive selection (or numeric fallback). Do not auto-select; require explicit confirmation.
- Malformed manifests: skip manifests that cannot be parsed; warn summarizing the file path and reason. Do not fail the entire operation unless all candidates are malformed.
- Missing `name` field: treat the file's basename (without extension) as the tool name for filename-based matching, but prefer `.name` when present.
- PATH collisions: if a command of the same name exists on PATH, warn and require explicit confirmation unless `--yes` or `--force` is passed. Use `command -v` to detect collisions.
- Existing target files: when a manifest or wrapper already exists in `$TARGET`, prompt to overwrite unless `--force` is provided. In non-interactive mode (`--yes`), only proceed to overwrite if `--force` is also passed.
- File system / permission errors: if the target directory cannot be created or is not writable, print a clear error (example shown in Failure & error examples) and exit with a non-zero code (>10).
- Symlinks: do not follow or resolve symlinks when reading manifests in the repo; operate on repository files only. When installing, write real files (not symlinks) to avoid cross-filesystem and Windows symlink limitations.
- RC file write failure: if `--append-path` is requested but the RC can't be modified due to permissions, print the intended export line and suggest manual addition; exit with a non-zero status.
- Cross-platform considerations: Windows/PowerShell support is out-of-scope for the first release; document limitations and accept future PRs to add support.

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
- Script implements exact-match install and wrapper creation and includes a `--no-wrapper` option.
- Interactive fuzzy selection works when `fzf` is installed; graceful numeric fallback works without it and `--no-fzf` forces non-fzf behavior.
- Tests covering primary flows exist and pass locally and in CI via a Makefile target (install-tests or integrated into shim-tests).
- Script documents usage and flags in README or man-style help output.
- Documentation includes example output for common failure modes and success cases, and the doc is marked 'Ready for implementation'.

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
  - Creates a fake `dotslash` shim in PATH when testing wrapper execution. For example:

# mkdir -p "$TMP/bin" && cat > "$TMP/bin/dotslash" <<'EOF'
# #!/usr/bin/env bash
# echo "DOTSLASH SHIM: "$@""
# EOF
# chmod +x "$TMP/bin/dotslash" && export PATH="$TMP/bin:$PATH"

  - Tests should assert (concrete cases):
    1) Exact match success
       - create a sample manifest with name "demo-tool" in a temp repo bin/
       - run: scripts/dotslash-install demo-tool
       - assert: $DOTSLASH_INSTALL_DIR/demo-tool.dotslash exists and $DOTSLASH_INSTALL_DIR/demo-tool wrapper exists and is executable
       - assert: invoking the wrapper execs the fake dotslash shim with the manifest path as the first argument

    2) No candidates
       - run: scripts/dotslash-install unknown-tool
       - assert: exit code 2 and helpful suggestions printed

    3) Missing dotslash
       - ensure PATH does not contain dotslash
       - run: scripts/dotslash-install demo-tool
       - assert: exit code 3 and actionable hint printed

    4) Path collision
       - ensure a conflicting command exists on PATH (create fake /tmp/bin/rg)
       - run: scripts/dotslash-install ripgrep and simulate interactive decline
       - assert: exit code 4

    5) --append-path modifies rc file
       - set TARGET to a temp dir not on PATH
       - provide a temp rc file path via env (e.g., DOTSLASH_RC)
       - run: scripts/dotslash-install --append-path demo-tool
       - assert: rc file contains the appended export line with the marker comment

    6) --force overwrites
       - create existing manifest and wrapper at target
       - run: scripts/dotslash-install --force demo-tool
       - assert: files are replaced

    7) --dry-run performs no writes
       - run: scripts/dotslash-install --dry-run demo-tool
       - assert: no files are written and output shows intended actions

- Add `install-tests` Makefile target that runs the script and integrates with `make shim-tests` when appropriate (see minimal example below).

Minimal Makefile target suggestion:

install-tests:
	./tests/dotslash_install_test.sh

- Ensure tests are resilient when `fzf` or `jq` are absent; skip or simulate these tools where needed. Use `command -v fzf` checks and set `--no-fzf` for deterministic tests when needed.

Decisions
---------
- Install dir resolution: DOTSLASH_INSTALL_DIR > XDG_BIN_HOME > XDG_DATA_HOME/dotslash/bin > $HOME/.dotslash/bin (see the "Default install directory resolution" section and example pseudocode).
- Verification of 'dotslash' presence: the script will verify that `dotslash` exists on PATH by default and exit with an actionable hint; use `--force-no-dotslash` to skip this check in constrained test environments.
- Interactive defaults: `fzf` is optional. When available it provides an enhanced interactive selection; otherwise the script falls back to a numeric prompt. Respect `--no-fzf` to force the fallback.
- Batch installs and strict manifest validation: deferred. Initial implementation will focus on single-manifest installs and will warn and skip malformed manifests rather than failing hard. Future iterations may add transactional multi-install support and stricter validation modes.

Open questions & decisions
--------------------------
- Platform-specific edge cases: For the initial release we will target POSIX-like systems (Linux and macOS). macOS will prefer ~/.bash_profile for bash shells when appropriate. Full Windows (PowerShell) support is out-of-scope for the first release and may be considered later.
- Batch installs: Deferred. The initial implementation will focus on single-manifest installs only. Adding support for installing multiple manifests in one invocation (and transactional behavior) is a candidate for a follow-up enhancement.
- Default install dir policy: Decision — honor DOTSLASH_INSTALL_DIR when set; otherwise prefer XDG_BIN_HOME if set; otherwise XDG_DATA_HOME/dotslash/bin if set; otherwise fallback to $HOME/.dotslash/bin. This balances explicit user control with XDG conventions.
- RC file modification: The script will never modify shell rc files without explicit opt-in via --append-path and explicit user confirmation. Any append will be idempotent and annotated with a clear marker comment.

PR checklist
------------
- [x] Add scripts/dotslash-install scaffold with usage and flags implemented and executable.
- [x] Add tests/dotslash_install_test.sh covering exact-match, selection fallback, missing-dotslash behavior, PATH append behavior, overwrite/force, dry-run, numeric selection fallback, fzf interactive flow (pseudo-tty test), jq fallback parsing, malformed manifest handling, and symlink skipping.
- [x] Add Makefile target `install-tests` and integrate with `make shim-tests` where appropriate.
- [x] Ensure tests are resilient when optional tools (fzf, jq) are missing; add simulation helpers where needed (tests skip or simulate fzf and jq when absent).
- [x] Update README.md with a short usage blurb and link to this proposal.
- [ ] Add a draft PR and request at least one reviewer; ensure CI runs and tests pass. (Requires pushing a branch and creating a PR; awaiting user instruction to proceed.)

Implementation status
---------------------
- Implementation complete: scripts/dotslash-install added and executable; test suite added and passing locally; Makefile target `install-tests` added; README updated.
- Remaining manual step: open a draft PR and request review (requires permission to push a branch). See next steps.


Next steps
----------
- Review this proposal and converge on CLI flags and default behavior. I can implement the scaffold (argument parsing + exact-match install) and tests, open a draft PR for review, and iterate on the interactive pieces (`fzf`/preview) once basic tests pass.
- Indicate whether you prefer XDG-style defaults or the documented precedence (DOTSLASH_INSTALL_DIR > XDG_BIN_HOME > XDG_DATA_HOME/dotslash/bin > $HOME/.dotslash/bin).