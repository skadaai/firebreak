#!/usr/bin/env bash
# Test runner for merge-conflict-resolver skill
# Runs comprehensive test suite with automatic cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEST_SUITE="$SCRIPT_DIR/merge-conflict-resolver-tests.json"
DEFAULT_TEST_FRAMEWORK="$SKILL_DIR/../skill-testing-framework/scripts/run_tests.py"
TEST_FRAMEWORK="${TEST_FRAMEWORK:-$DEFAULT_TEST_FRAMEWORK}"
TMP_TEST_SUITE=$(mktemp)
trap 'rm -f "$TMP_TEST_SUITE"' EXIT INT TERM

if ! [ -f "$TEST_FRAMEWORK" ]; then
  echo "missing test framework: $TEST_FRAMEWORK" >&2
  echo "set TEST_FRAMEWORK to the skill-testing-framework run_tests.py path before running this script" >&2
  exit 1
fi

awk -v skill_path="$SKILL_DIR" '{
  gsub(/\$\{SKILL_PATH\}/, skill_path)
  print
}' "$TEST_SUITE" >"$TMP_TEST_SUITE"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Merge Conflict Resolver - Test Suite Runner           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Run tests
echo "Running test suite..."
echo ""

python3 "$TEST_FRAMEWORK" "$TMP_TEST_SUITE" --skill-path "$SKILL_DIR"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Test Run Complete                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
