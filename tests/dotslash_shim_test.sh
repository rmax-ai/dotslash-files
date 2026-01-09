#!/usr/bin/env bash
set -euo pipefail

# tests/dotslash_shim_test.sh
# Tests for dotslash-shim using dotslash-sandbox.

# Ensure we are in the project root
cd "$(dirname "$0")/.."

SANDBOX="./scripts/dotslash-sandbox"
FIXTURE="tests/fixtures/install_shim.dotslash"

# Check if podman is available
if ! command -v podman >/dev/null 2>&1; then
    echo "podman not found, skipping tests."
    exit 0
fi

# Create a temporary directory for mocks inside the workspace to avoid mount issues on macOS
MOCK_DIR=$(mktemp -d "$PWD/tests/mocks.XXXXXX")
trap 'rm -rf "$MOCK_DIR"' EXIT

# Isolate cache to ensure dotslash-sandbox cache is empty
export SANDBOX_CACHE_DIR="$MOCK_DIR/cache"
mkdir -p "$SANDBOX_CACHE_DIR"

echo "Starting dotslash-shim tests..."

# 1. Test DOTSLASH_BIN: Directly run a provided binary without installation
echo "[Test 1] DOTSLASH_BIN override"
cat > "$MOCK_DIR/fake-dotslash" <<'EOF'
#!/bin/sh
echo "Fake dotslash called with args: $@"
EOF
chmod +x "$MOCK_DIR/fake-dotslash"

export SANDBOX_ADDITIONAL_PATH="$MOCK_DIR"
export SANDBOX_ENV="DOTSLASH_BIN"
export DOTSLASH_BIN="/extra_bin/fake-dotslash"
OUTPUT=$( "$SANDBOX" "$FIXTURE" test_arg 2>&1 )

if [[ "$OUTPUT" == *"Fake dotslash called with args: --from-install test_arg"* ]]; then
    echo "✓ DOTSLASH_BIN override passed"
else
    echo "✗ DOTSLASH_BIN override failed"
    echo "Output was: $OUTPUT"
    exit 1
fi

# 2. Test installation trigger and DOTSLASH_CACHE_DIR
echo "[Test 2] DOTSLASH_CACHE_DIR and installation"
# Mock curl to "download" a fake tarball
# dotslash-shim calls: curl -LSfs "$URL" -o "$TMP_ARCHIVE"
cat > "$MOCK_DIR/curl" <<'EOF'
#!/bin/sh
# $2 is URL, $4 is output file
echo "Mock curl downloading from $2"
WORKDIR=$(mktemp -d)
echo '#!/bin/sh' > "$WORKDIR/dotslash"
echo 'echo "Mock binary executed"' >> "$WORKDIR/dotslash"
chmod +x "$WORKDIR/dotslash"
tar -czf "$4" -C "$WORKDIR" dotslash
EOF
chmod +x "$MOCK_DIR/curl"

# We also need to mock sha256sum/shasum if we don't skip verify,
# but using DOTSLASH_SKIP_VERIFY is easier for this test.
export SANDBOX_ADDITIONAL_PATH="$MOCK_DIR"
export SANDBOX_ENV="DOTSLASH_CACHE_DIR DOTSLASH_SKIP_VERIFY"
export DOTSLASH_CACHE_DIR="/tmp/custom-cache"
export DOTSLASH_SKIP_VERIFY="1"
unset DOTSLASH_BIN # Ensure we don't use the previous test's BIN

OUTPUT=$( "$SANDBOX" "$FIXTURE" 2>&1 ) || EXIT_CODE=$?
echo "Exit code: ${EXIT_CODE:-0}"

if [[ "$OUTPUT" == *"[dotslash-shim] Installing dotslash..."* ]] && [[ "$OUTPUT" == *"Mock binary executed"* ]]; then
    echo "✓ DOTSLASH_CACHE_DIR and installation passed"
else
    echo "✗ DOTSLASH_CACHE_DIR and installation failed"
    echo "Output was: $OUTPUT"
    exit 1
fi

# 3. Test DOTSLASH_VERSION
echo "[Test 3] DOTSLASH_VERSION"
export DOTSLASH_VERSION="v1.2.3-test"
export DOTSLASH_CACHE_DIR="/tmp/test3-cache"
export SANDBOX_ENV="DOTSLASH_VERSION DOTSLASH_SKIP_VERIFY DOTSLASH_CACHE_DIR"
export DOTSLASH_SKIP_VERIFY="1"

OUTPUT=$( "$SANDBOX" "$FIXTURE" 2>&1 ) || true

if [[ "$OUTPUT" == *"Mock curl downloading from https://github.com/facebook/dotslash/releases/download/v1.2.3-test/"* ]]; then
    echo "✓ DOTSLASH_VERSION passed"
else
    echo "✗ DOTSLASH_VERSION failed"
    echo "Output was: $OUTPUT"
    exit 1
fi

echo "All dotslash-shim tests passed!"
