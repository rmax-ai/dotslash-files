#!/usr/bin/env bash
set -euo pipefail

# tests/dotslash_sandbox_integration_test.sh
# Integration tests for dotslash-sandbox.

# Ensure we are in the project root
cd "$(dirname "$0")/.."

SANDBOX="./scripts/dotslash-sandbox"

# Check if podman is available
if ! command -v podman >/dev/null 2>&1; then
    echo "podman not found, skipping tests."
    exit 0
fi

# Create a temporary directory for test artifacts
TEST_DIR=$(mktemp -d "$PWD/tests/sandbox_test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

# Isolate cache
export SANDBOX_CACHE_DIR="$TEST_DIR/cache"
mkdir -p "$SANDBOX_CACHE_DIR"

# Clear any potentially inherited variables that might break relative paths or mount logic
unset SANDBOX_ADDITIONAL_PATH
unset SANDBOX_OUTPUT
unset SANDBOX_OFFLINE

echo "Starting dotslash-sandbox integration tests..."

# 1. Test Environment Passthrough (SANDBOX_ENV)
echo "[Test 1] Environment passthrough"
FIXTURE_ENV="$TEST_DIR/env_test.dotslash"
cat > "$FIXTURE_ENV" <<'EOF'
#!/bin/sh
if [ "$MY_TEST_VAR" = "hello-world" ]; then
    echo "Passthrough success"
else
    echo "Passthrough failed: MY_TEST_VAR='$MY_TEST_VAR'"
    exit 1
fi
EOF
chmod +x "$FIXTURE_ENV"

export SANDBOX_ENV="MY_TEST_VAR"
export MY_TEST_VAR="hello-world"
OUTPUT=$( "$SANDBOX" "$FIXTURE_ENV" 2>&1 )
if [[ "$OUTPUT" == *"Passthrough success"* ]]; then
    echo "✓ Environment passthrough passed"
else
    echo "✗ Environment passthrough failed"
    echo "$OUTPUT"
    exit 1
fi

# 2. Test Output Mount (SANDBOX_OUTPUT)
echo "[Test 2] Output mount"
FIXTURE_OUT="$TEST_DIR/output_test.dotslash"
cat > "$FIXTURE_OUT" <<'EOF'
#!/bin/sh
echo "data from container" > /output/test_result.txt
EOF
chmod +x "$FIXTURE_OUT"

mkdir -p "$TEST_DIR/output_dir"
export SANDBOX_OUTPUT="$TEST_DIR/output_dir"
export SANDBOX_ENV="" # Clear previous
OUTPUT=$( "$SANDBOX" "$FIXTURE_OUT" 2>&1 ) || EXIT_CODE=$?

if [[ -f "$TEST_DIR/output_dir/test_result.txt" ]] && [[ "$(cat "$TEST_DIR/output_dir/test_result.txt")" == "data from container" ]]; then
    echo "✓ Output mount passed"
else
    echo "✗ Output mount failed"
    exit 1
fi

# 3. Test Additional Path (SANDBOX_ADDITIONAL_PATH)
echo "[Test 3] Additional path"
MOCK_BIN_DIR="$TEST_DIR/extra_bin"
mkdir -p "$MOCK_BIN_DIR"
cat > "$MOCK_BIN_DIR/helper-tool" <<'EOF'
#!/bin/sh
echo "helper called"
EOF
chmod +x "$MOCK_BIN_DIR/helper-tool"

FIXTURE_ADD="$TEST_DIR/path_test.dotslash"
cat > "$FIXTURE_ADD" <<'EOF'
#!/bin/sh
helper-tool
EOF
chmod +x "$FIXTURE_ADD"

export SANDBOX_ADDITIONAL_PATH="$MOCK_BIN_DIR"
OUTPUT=$( "$SANDBOX" "$FIXTURE_ADD" 2>&1 )
if [[ "$OUTPUT" == *"helper called"* ]]; then
    echo "✓ Additional path passed"
else
    echo "✗ Additional path failed"
    echo "$OUTPUT"
    exit 1
fi

# 4. Test Offline Mode (SANDBOX_OFFLINE)
echo "[Test 4] Offline mode"
FIXTURE_NET="$TEST_DIR/net_test.dotslash"
cat > "$FIXTURE_NET" <<'EOF'
#!/bin/sh
# Try to ping something; in offline mode this should fail immediately or be blocked
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "Network is up"
else
    echo "Network is down"
fi
EOF
chmod +x "$FIXTURE_NET"

export SANDBOX_OFFLINE=1
OUTPUT=$( "$SANDBOX" "$FIXTURE_NET" 2>&1 )
if [[ "$OUTPUT" == *"Network is down"* ]]; then
    echo "✓ Offline mode passed"
else
    echo "✗ Offline mode failed"
    echo "$OUTPUT"
    exit 1
fi

echo "All dotslash-sandbox integration tests passed!"
