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
# Remove the fake dotslash from PATH
export PATH="$(echo $PATH | sed -e 's~$FAKE_BIN:~~')"

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

echo "Test 3 passed: dry-run"

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
