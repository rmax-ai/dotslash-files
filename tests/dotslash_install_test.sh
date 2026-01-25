#!/usr/bin/env bash
set -euo pipefail

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Setup: create a fake repo structure
REPO_ROOT="$TMPDIR/repo"
mkdir -p "$REPO_ROOT/bin"

# Sample manifest
cat >"$REPO_ROOT/bin/demo-tool.dotslash" <<'EOF'
#!/usr/bin/env dotslash
{
  "name": "demo-tool",
  "provider": { "http": "https://example.com/demo-tool.tar.gz" },
  "run": { "cmd": ["demo-tool"] }
}
EOF
chmod +x "$REPO_ROOT/bin/demo-tool.dotslash"

# Create a fake dotslash shim in PATH
FAKE_BIN="$TMPDIR/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/dotslash" <<'EOF'
#!/usr/bin/env bash
# echo to stdout so test can assert
echo "DOTSLASH SHIM: $@"
EOF
chmod +x "$FAKE_BIN/dotslash"
export PATH="$FAKE_BIN:$PATH"

# Point script to use REPO_ROOT by invoking it from scripts/ with CWD = REPO_ROOT parent
SCRIPTS_DIR="$(pwd)/scripts"

# Test 1: Exact match installs manifest and wrapper
export DOTSLASH_INSTALL_DIR="$TMPDIR/install"
mkdir -p "$DOTSLASH_INSTALL_DIR"

# Run the installer
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" demo-tool)

if [ ! -f "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" ]; then
  echo "Test failed: manifest not installed"
  exit 1
fi
if [ ! -x "$DOTSLASH_INSTALL_DIR/demo-tool" ]; then
  echo "Test failed: wrapper not created or not executable"
  exit 1
fi
# Invoke the wrapper and ensure it calls the fake dotslash shim
OUT="$($DOTSLASH_INSTALL_DIR/demo-tool --version)"
if ! echo "$OUT" | grep -q "DOTSLASH SHIM"; then
  echo "Test failed: wrapper did not invoke dotslash shim"
  exit 1
fi

echo "Test 1 passed: exact match install"

# Test 2: Missing dotslash behavior
# Temporarily remove any PATH entries that contain an executable named 'dotslash'
ORIG_PATH="$PATH"
NEWPATH=""
IFS=:
for p in $ORIG_PATH; do
  if [ ! -x "$p/dotslash" ]; then
    if [ -z "$NEWPATH" ]; then
      NEWPATH="$p"
    else
      NEWPATH="$NEWPATH:$p"
    fi
  fi
done
unset IFS
PATH="$NEWPATH"
# Sanity check: ensure dotslash is not found
if command -v dotslash >/dev/null 2>&1; then
  echo "Test setup failed: dotslash still found on PATH"
  PATH="$ORIG_PATH"
  exit 1
fi

# Run the installer; it should install a local dotslash shim into the target and succeed.
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --force demo-tool)

if [ ! -x "$DOTSLASH_INSTALL_DIR/dotslash" ]; then
  echo "Test failed: expected dotslash shim installed at $DOTSLASH_INSTALL_DIR/dotslash"
  PATH="$ORIG_PATH"
  exit 1
fi

echo "Test 2 passed: missing dotslash auto-shim install"

# Restore PATH for subsequent tests
PATH="$ORIG_PATH"

# Test 3: Dry-run does not write files
export PATH="$FAKE_BIN:$PATH"
rm -f "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --dry-run demo-tool)
if [ -f "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" ] || [ -f "$DOTSLASH_INSTALL_DIR/demo-tool" ]; then
  echo "Test failed: dry-run should not create files"
  exit 1
fi

# Run dry-run with --append-path to verify no rc modification takes place
RC_TEMP="$TMPDIR/rc"
cat >"$RC_TEMP" <<'EOF'
# empty rc
EOF
chmod 0644 "$RC_TEMP"
# Override SHELL to force detection and simulate writing to RC
OLD_SHELL="$SHELL"
export SHELL="/bin/bash"
# Use HOME to point to TMPDIR so the rc file is $HOME/.bashrc
OLD_HOME="$HOME"
export HOME="$TMPDIR"
mv "$RC_TEMP" "$HOME/.bashrc"
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --dry-run --append-path demo-tool)
# ensure the rc file was not modified
if grep -q "added by dotslash-install" "$HOME/.bashrc"; then
  echo "Test failed: dry-run --append-path should not modify rc file"
  export HOME="$OLD_HOME"
  export SHELL="$OLD_SHELL"
  exit 1
fi
# restore
export HOME="$OLD_HOME"
export SHELL="$OLD_SHELL"

echo "Test 3 passed: dry-run and --append-path behavior verified"

# Test 5: --append-path modifies rc file (idempotent)
export PATH="$FAKE_BIN:$PATH"
export HOME="$TMPDIR"
export SHELL="/bin/bash"
# Ensure target not on PATH (DOTSLASH_INSTALL_DIR is not on PATH)
export DOTSLASH_INSTALL_DIR="$TMPDIR/install"
rm -rf "$DOTSLASH_INSTALL_DIR" && mkdir -p "$DOTSLASH_INSTALL_DIR"
# Clean rc
RC_FILE="$HOME/.bashrc"
rm -f "$RC_FILE"

# Run installer with --append-path to modify rc
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --append-path --yes demo-tool)
if ! grep -q "# added by dotslash-install" "$RC_FILE"; then
  echo "Test failed: --append-path should append to RC file"
  exit 1
fi
# Run again to test idempotency
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --append-path --yes demo-tool)
COUNT=$(grep -c "# added by dotslash-install" "$RC_FILE" || true)
if [ "$COUNT" -ne 1 ]; then
  echo "Test failed: --append-path should be idempotent (expected 1 marker, got $COUNT)"
  exit 1
fi

echo "Test 5 passed: --append-path modifies rc file and is idempotent"

# Restore HOME and SHELL
export HOME="$OLD_HOME"
export SHELL="$OLD_SHELL"

# Test 4: No candidates
set +e
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" unknown-tool)
STATUS=$?
set -e
if [ $STATUS -ne 2 ]; then
  echo "Test failed: expected exit code 2 for unknown candidate, got $STATUS"
  exit 1
fi

echo "Test 4 passed: unknown candidate"

# Test 6: Numeric selection fallback (no fzf)
# Create two new manifests that match the same query
cat >"$REPO_ROOT/bin/seltest-1.dotslash" <<'EOF'
#!/usr/bin/env dotslash
{
  "name": "seltest-1",
  "provider": { "http": "https://example.com/seltest-1.tar.gz" },
  "run": { "cmd": ["seltest-1"] }
}
EOF
chmod +x "$REPO_ROOT/bin/seltest-1.dotslash"
cat >"$REPO_ROOT/bin/seltest-2.dotslash" <<'EOF'
#!/usr/bin/env dotslash
{
  "name": "seltest-2",
  "provider": { "http": "https://example.com/seltest-2.tar.gz" },
  "run": { "cmd": ["seltest-2"] }
}
EOF
chmod +x "$REPO_ROOT/bin/seltest-2.dotslash"

# Compute the matching indices the same way the installer would and pick the index for seltest-2
MATCH_IDX=""
idx=0
for f in "$REPO_ROOT/bin"/*.dotslash; do
  name=""
  if command -v jq >/dev/null 2>&1; then
    name=$(jq -r '.name // empty' "$f" 2>/dev/null || true)
  fi
  if [ -z "$name" ]; then
    if grep -q '"name"' "$f" 2>/dev/null; then
      name=$(sed -n 's/.*"name"\s*:\s*\"\([^\"]*\)\".*/\1/p' "$f" | head -n1 || true)
    fi
  fi
  if [ -z "$name" ]; then
    name="$(basename "$f" .dotslash)"
  fi
  fname="$(basename "$f")"
  if echo "$fname" | grep -qi "seltest"; then
    if [ "$(basename "$f" .dotslash)" = "seltest-2" ]; then
      MATCH_IDX="$idx"
      break
    fi
  fi
  idx=$((idx + 1))
done

if [ -z "$MATCH_IDX" ]; then
  echo "Test setup failed: could not determine match index for seltest-2"
  exit 1
fi

# Run installer and provide the numeric selection
export DOTSLASH_INSTALL_DIR="$TMPDIR/install_sel"
mkdir -p "$DOTSLASH_INSTALL_DIR"
printf '%s
' "$MATCH_IDX" | (cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" -n seltest)
# verify seltest-2 was installed
if [ ! -f "$DOTSLASH_INSTALL_DIR/seltest-2.dotslash" ] || [ ! -x "$DOTSLASH_INSTALL_DIR/seltest-2" ]; then
  echo "Test failed: numeric selection did not install expected candidate"
  exit 1
fi

echo "Test 6 passed: numeric selection fallback"

# Test 7: --force overwrites existing files
export DOTSLASH_INSTALL_DIR="$TMPDIR/install_force"
mkdir -p "$DOTSLASH_INSTALL_DIR"
# Create existing manifest and wrapper with sentinel content
printf 'OLD' >"$DOTSLASH_INSTALL_DIR/demo-tool.dotslash"
printf 'OLDWRAPPER' >"$DOTSLASH_INSTALL_DIR/demo-tool"
chmod +x "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"
# Run installer with --force
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --force demo-tool)
# Verify files were overwritten (wrapper should contain exec dotslash)
if ! grep -q "exec dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"; then
  echo "Test failed: --force did not overwrite wrapper"
  exit 1
fi
if ! grep -q "provider" "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash"; then
  echo "Test failed: --force did not overwrite manifest"
  exit 1
fi

echo "Test 7 passed: --force overwrites existing files"

# Test 8: --yes does not overwrite existing files (non-destructive)
export DOTSLASH_INSTALL_DIR="$TMPDIR/install_yes"
mkdir -p "$DOTSLASH_INSTALL_DIR"
# Create existing manifest and wrapper with sentinel content
printf 'OLD' >"$DOTSLASH_INSTALL_DIR/demo-tool.dotslash"
printf 'OLDWRAPPER' >"$DOTSLASH_INSTALL_DIR/demo-tool"
chmod +x "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"
# Run installer with --yes (should skip overwriting)
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --yes demo-tool)
# Verify files were NOT overwritten
if grep -q "exec dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"; then
  echo "Test failed: --yes should not have overwritten wrapper"
  exit 1
fi
if grep -q "provider" "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash"; then
  echo "Test failed: --yes should not have overwritten manifest"
  exit 1
fi

echo "Test 8 passed: --yes non-destructive"

# Test 9: --force --yes overwrites
export DOTSLASH_INSTALL_DIR="$TMPDIR/install_force_yes"
mkdir -p "$DOTSLASH_INSTALL_DIR"
printf 'OLD' >"$DOTSLASH_INSTALL_DIR/demo-tool.dotslash"
printf 'OLDWRAPPER' >"$DOTSLASH_INSTALL_DIR/demo-tool"
chmod +x "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --force --yes demo-tool)
if ! grep -q "exec dotslash" "$DOTSLASH_INSTALL_DIR/demo-tool"; then
  echo "Test failed: --force --yes did not overwrite wrapper"
  exit 1
fi

echo "Test 9 passed: --force --yes overwrites"

# Test 10: Path collision prompts and respects response
# Create fake command on PATH with same name
FAKE_COL_BIN="$TMPDIR/fakecol"
mkdir -p "$FAKE_COL_BIN"
cat >"$FAKE_COL_BIN/demo-tool" <<'EOF'
#!/usr/bin/env bash
echo "I AM ANOTHER demo-tool"
EOF
chmod +x "$FAKE_COL_BIN/demo-tool"
# Put it at front of PATH
export PATH="$FAKE_COL_BIN:$PATH"
# Simulate user declining (n)
set +e
printf 'n
' | (cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" demo-tool)
STATUS=$?
set -e
if [ $STATUS -ne 4 ]; then
  echo "Test failed: expected exit code 4 when user declines PATH collision prompt, got $STATUS"
  exit 1
fi
# Now simulate accepting via --yes non-interactive
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --yes demo-tool)
if [ ! -f "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" ]; then
  echo "Test failed: --yes should proceed despite PATH collision"
  exit 1
fi

echo "Test 10 passed: PATH collision prompt behavior"

# Restore PATH to include fake dotslash shim at front for next tests
export PATH="$FAKE_BIN:$PATH"

# Test 11: --force-no-dotslash proceeds when dotslash missing
# Temporarily remove any PATH entries that contain an executable named 'dotslash'
ORIG_PATH="$PATH"
NEWPATH=""
IFS=:
for p in $ORIG_PATH; do
  if [ ! -x "$p/dotslash" ]; then
    if [ -z "$NEWPATH" ]; then
      NEWPATH="$p"
    else
      NEWPATH="$NEWPATH:$p"
    fi
  fi
done
unset IFS
PATH="$NEWPATH"
# Sanity check: ensure dotslash is not found
if command -v dotslash >/dev/null 2>&1; then
  echo "Test setup failed: dotslash still found on PATH"
  PATH="$ORIG_PATH"
  exit 1
fi
# Run installer with --force-no-dotslash (should proceed)
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --force-no-dotslash demo-tool)
if [ $? -ne 0 ]; then
  echo "Test failed: --force-no-dotslash should allow the installer to proceed"
  PATH="$ORIG_PATH"
  exit 1
fi
# Restore PATH
PATH="$ORIG_PATH"

echo "Test 11 passed: --force-no-dotslash proceeds when dotslash missing"

# Test 12: Help output
OUT="$($SCRIPTS_DIR/dotslash-install -h 2>&1 || true)"
if ! echo "$OUT" | grep -q "Usage:"; then
  echo "Test failed: -h did not print usage"
  exit 1
fi

echo "Test 12 passed: help output"

# Test 13: --no-wrapper does not create wrapper
export DOTSLASH_INSTALL_DIR="$TMPDIR/install_nowrapper"
rm -rf "$DOTSLASH_INSTALL_DIR" && mkdir -p "$DOTSLASH_INSTALL_DIR"
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" --no-wrapper demo-tool)
if [ ! -f "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" ]; then
  echo "Test failed: --no-wrapper should still copy the manifest"
  exit 1
fi
if [ -f "$DOTSLASH_INSTALL_DIR/demo-tool" ]; then
  echo "Test failed: --no-wrapper should not create a wrapper file"
  exit 1
fi

echo "Test 13 passed: --no-wrapper behavior verified"

# Test 14: manifest is executable after install
export DOTSLASH_INSTALL_DIR="$TMPDIR/install_exec"
rm -rf "$DOTSLASH_INSTALL_DIR" && mkdir -p "$DOTSLASH_INSTALL_DIR"
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" demo-tool)
if [ ! -x "$DOTSLASH_INSTALL_DIR/demo-tool.dotslash" ]; then
  echo "Test failed: manifest should be executable after install"
  exit 1
fi

echo "Test 14 passed: manifest executable"

# Done
echo "All tests passed."
