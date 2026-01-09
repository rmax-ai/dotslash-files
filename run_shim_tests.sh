#!/usr/bin/env bash
set -euo pipefail

# run_shim_tests.sh
# Main test runner for dotslash-files (renamed from run_tests.sh).

# Ensure we are in the project root
cd "$(dirname "$0")"

echo "Running all tests..."
echo "========================================"

# Check dependencies
if ! command -v podman >/dev/null 2>&1; then
    echo "Warning: podman not found. Sandbox-based tests will be skipped."
fi

# Run Shim tests
echo "Running dotslash-shim tests..."
./tests/dotslash_shim_test.sh
echo "----------------------------------------"

# Run Sandbox integration tests
echo "Running dotslash-sandbox integration tests..."
./tests/dotslash_sandbox_integration_test.sh
echo "----------------------------------------"

echo "All test suites completed successfully!"
