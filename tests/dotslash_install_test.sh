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

# Run the installer expecting exit code 3
set +e
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" demo-tool)
STATUS=$?
set -e
if [ $STATUS -ne 3 ]; then
  echo "Test failed: expected exit code 3 when dotslash missing, got $STATUS"
  PATH="$ORIG_PATH"
  exit 1
fi

echo "Test 2 passed: missing dotslash behavior"

# Restore PATH for subsequent tests
PATH="$ORIG_PATH"

echo "Test 2 passed: missing dotslash behavior"

set +e
(cd "$REPO_ROOT" && "$SCRIPTS_DIR/dotslash-install" demo-tool)
STATUS=$?
set -e
if [ $STATUS -ne 3 ]; then
  echo "Test failed: expected exit code 3 when dotslash missing, got $STATUS"
  exit 1
fi

echo "Test 2 passed: missing dotslash behavior"

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

# Done
echo "All tests passed."
