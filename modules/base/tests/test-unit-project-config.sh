#!/usr/bin/env bash
# Unit tests for firebreak-project-config.sh functions.
# These tests source the script directly and exercise individual functions.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_CONFIG_LIB="$SCRIPT_DIR/../host/firebreak-project-config.sh"

if ! [ -f "$PROJECT_CONFIG_LIB" ]; then
  echo "test-unit-project-config: cannot find firebreak-project-config.sh at $PROJECT_CONFIG_LIB" >&2
  exit 1
fi

# shellcheck source=../host/firebreak-project-config.sh
. "$PROJECT_CONFIG_LIB"

pass_count=0
fail_count=0

assert_eq() {
  description=$1
  actual=$2
  expected=$3
  if [ "$actual" = "$expected" ]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  expected: $(printf '%s' "$expected" | cat -A)" >&2
    echo "  actual:   $(printf '%s' "$actual" | cat -A)" >&2
  fi
}

assert_contains() {
  description=$1
  haystack=$2
  needle=$3
  if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  did not find: $needle" >&2
    echo "  in: $haystack" >&2
  fi
}

assert_not_contains() {
  description=$1
  haystack=$2
  needle=$3
  if ! printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description" >&2
    echo "  unexpectedly found: $needle" >&2
    echo "  in: $haystack" >&2
  fi
}

assert_return_zero() {
  description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description (expected exit 0)" >&2
  fi
}

assert_return_nonzero() {
  description=$1
  shift
  if ! "$@" >/dev/null 2>&1; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $description (expected nonzero exit)" >&2
  fi
}

# ---------------------------------------------------------------------------
# trim_whitespace
# ---------------------------------------------------------------------------

result=$(trim_whitespace "  hello  ")
assert_eq "trim_whitespace strips leading and trailing spaces" "$result" "hello"

result=$(trim_whitespace "	tabs	")
assert_eq "trim_whitespace strips leading and trailing tabs" "$result" "tabs"

result=$(trim_whitespace "no-spaces")
assert_eq "trim_whitespace leaves a value with no spaces unchanged" "$result" "no-spaces"

result=$(trim_whitespace "")
assert_eq "trim_whitespace handles empty string" "$result" ""

result=$(trim_whitespace "   ")
assert_eq "trim_whitespace returns empty for all-whitespace string" "$result" ""

result=$(trim_whitespace "  hello world  ")
assert_eq "trim_whitespace preserves internal spaces" "$result" "hello world"

result=$(trim_whitespace "value=with=equals")
assert_eq "trim_whitespace preserves equals signs" "$result" "value=with=equals"

# ---------------------------------------------------------------------------
# firebreak_reset_project_config_state
# ---------------------------------------------------------------------------

FIREBREAK_RESOLVED_PROJECT_ROOT="some-root"
FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE="git"
FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE="/some/file"
FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE="project-default"
FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS="SOME_KEY"

firebreak_reset_project_config_state

assert_eq "reset clears FIREBREAK_RESOLVED_PROJECT_ROOT" "$FIREBREAK_RESOLVED_PROJECT_ROOT" ""
assert_eq "reset clears FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE" "$FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE" ""
assert_eq "reset clears FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE" "$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE" ""
assert_eq "reset sets FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE to none" "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE" "none"
assert_eq "reset clears FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" ""

# ---------------------------------------------------------------------------
# firebreak_project_config_key_allowed
# ---------------------------------------------------------------------------

assert_return_zero "AGENT_CONFIG is allowed" firebreak_project_config_key_allowed "AGENT_CONFIG"
assert_return_zero "AGENT_CONFIG_HOST_PATH is allowed" firebreak_project_config_key_allowed "AGENT_CONFIG_HOST_PATH"
assert_return_zero "FIREBREAK_VM_MODE is allowed" firebreak_project_config_key_allowed "FIREBREAK_VM_MODE"
assert_return_zero "CODEX_CONFIG is allowed" firebreak_project_config_key_allowed "CODEX_CONFIG"
assert_return_zero "CODEX_CONFIG_HOST_PATH is allowed" firebreak_project_config_key_allowed "CODEX_CONFIG_HOST_PATH"
assert_return_zero "CLAUDE_CONFIG is allowed" firebreak_project_config_key_allowed "CLAUDE_CONFIG"
assert_return_zero "CLAUDE_CONFIG_HOST_PATH is allowed" firebreak_project_config_key_allowed "CLAUDE_CONFIG_HOST_PATH"

assert_return_nonzero "FIREBREAK_TASK_STATE_DIR is not allowed" firebreak_project_config_key_allowed "FIREBREAK_TASK_STATE_DIR"
assert_return_nonzero "FIREBREAK_TMPDIR is not allowed" firebreak_project_config_key_allowed "FIREBREAK_TMPDIR"
assert_return_nonzero "PATH is not allowed" firebreak_project_config_key_allowed "PATH"
assert_return_nonzero "HOME is not allowed" firebreak_project_config_key_allowed "HOME"
assert_return_nonzero "FIREBREAK_LAUNCHER_KVM_PATH is not allowed" firebreak_project_config_key_allowed "FIREBREAK_LAUNCHER_KVM_PATH"
assert_return_nonzero "AGENT_VM_ENTRYPOINT is not allowed" firebreak_project_config_key_allowed "AGENT_VM_ENTRYPOINT"
assert_return_nonzero "FIREBREAK_AGENT_MODE is not allowed" firebreak_project_config_key_allowed "FIREBREAK_AGENT_MODE"
assert_return_nonzero "empty string is not allowed" firebreak_project_config_key_allowed ""

# ---------------------------------------------------------------------------
# firebreak_record_ignored_key
# ---------------------------------------------------------------------------

FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS=""

firebreak_record_ignored_key "SOME_KEY"
assert_contains "record_ignored_key adds a key" "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" "SOME_KEY"

firebreak_record_ignored_key "ANOTHER_KEY"
assert_contains "record_ignored_key can add a second key" "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" "ANOTHER_KEY"
assert_contains "first key still present after adding second" "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" "SOME_KEY"

# Adding same key again should not duplicate
firebreak_record_ignored_key "SOME_KEY"
count=$(printf '%s\n' "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" | grep -c "SOME_KEY" || true)
assert_eq "record_ignored_key does not duplicate existing key" "$count" "1"

# ---------------------------------------------------------------------------
# firebreak_record_original_env_key and firebreak_original_env_has_key
# ---------------------------------------------------------------------------

FIREBREAK_ORIGINAL_ENV_KEYS=""

firebreak_record_original_env_key "MY_ORIGINAL_KEY"
assert_return_zero "original_env_has_key returns true for recorded key" firebreak_original_env_has_key "MY_ORIGINAL_KEY"
assert_return_nonzero "original_env_has_key returns false for unrecorded key" firebreak_original_env_has_key "NOT_RECORDED"

# Adding same key again should not duplicate
firebreak_record_original_env_key "MY_ORIGINAL_KEY"
count=$(printf '%s\n' "$FIREBREAK_ORIGINAL_ENV_KEYS" | grep -c "MY_ORIGINAL_KEY" || true)
assert_eq "record_original_env_key does not duplicate existing key" "$count" "1"

# ---------------------------------------------------------------------------
# firebreak_load_project_config with a temporary config file
# ---------------------------------------------------------------------------

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

config_file="$tmp_dir/.firebreak.env"

# Test: basic key-value loading
cat >"$config_file" <<'EOF'
AGENT_CONFIG=workspace
FIREBREAK_VM_MODE=run
EOF

unset AGENT_CONFIG FIREBREAK_VM_MODE 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config sets AGENT_CONFIG from file" "${AGENT_CONFIG:-}" "workspace"
assert_eq "load_project_config sets FIREBREAK_VM_MODE from file" "${FIREBREAK_VM_MODE:-}" "run"
assert_eq "load_project_config sets config source to env" "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE" "env"

unset AGENT_CONFIG FIREBREAK_VM_MODE FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: comments and blank lines are ignored
cat >"$config_file" <<'EOF'
# This is a comment
AGENT_CONFIG=vm

# Another comment
CODEX_CONFIG=host
EOF

unset AGENT_CONFIG CODEX_CONFIG 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config ignores comment lines" "${AGENT_CONFIG:-}" "vm"
assert_eq "load_project_config ignores blank lines" "${CODEX_CONFIG:-}" "host"

unset AGENT_CONFIG CODEX_CONFIG FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: unsupported internal keys are tracked as ignored
cat >"$config_file" <<'EOF'
AGENT_CONFIG=workspace
FIREBREAK_TASK_STATE_DIR=/tmp/internal
FIREBREAK_TMPDIR=/tmp/also-internal
EOF

unset AGENT_CONFIG FIREBREAK_TASK_STATE_DIR FIREBREAK_TMPDIR 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config loads allowed keys" "${AGENT_CONFIG:-}" "workspace"
assert_contains "load_project_config tracks FIREBREAK_TASK_STATE_DIR as ignored" "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" "FIREBREAK_TASK_STATE_DIR"
assert_contains "load_project_config tracks FIREBREAK_TMPDIR as ignored" "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" "FIREBREAK_TMPDIR"
# Ensure the internal key was NOT actually set
assert_eq "load_project_config does not apply internal keys" "${FIREBREAK_TASK_STATE_DIR:-}" ""

unset AGENT_CONFIG FIREBREAK_TASK_STATE_DIR FIREBREAK_TMPDIR FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: environment variable takes precedence over file value
cat >"$config_file" <<'EOF'
AGENT_CONFIG=workspace
FIREBREAK_VM_MODE=run
EOF

export AGENT_CONFIG=vm
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "env var AGENT_CONFIG takes precedence over file value" "${AGENT_CONFIG:-}" "vm"

unset AGENT_CONFIG FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: double-quoted values are unquoted
cat >"$config_file" <<'EOF'
AGENT_CONFIG="host"
CODEX_CONFIG_HOST_PATH="/home/user/.codex"
EOF

unset AGENT_CONFIG CODEX_CONFIG_HOST_PATH 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config strips double quotes from values" "${AGENT_CONFIG:-}" "host"
assert_eq "load_project_config strips double quotes from path values" "${CODEX_CONFIG_HOST_PATH:-}" "/home/user/.codex"

unset AGENT_CONFIG CODEX_CONFIG_HOST_PATH FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: single-quoted values are unquoted
cat >"$config_file" <<'EOF'
AGENT_CONFIG='workspace'
CLAUDE_CONFIG_HOST_PATH='~/.claude'
EOF

unset AGENT_CONFIG CLAUDE_CONFIG_HOST_PATH 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config strips single quotes from values" "${AGENT_CONFIG:-}" "workspace"
assert_eq "load_project_config strips single quotes from path values" "${CLAUDE_CONFIG_HOST_PATH:-}" "~/.claude"

unset AGENT_CONFIG CLAUDE_CONFIG_HOST_PATH FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: missing file is not an error
nonexistent_file="$tmp_dir/does-not-exist/.firebreak.env"
FIREBREAK_PROJECT_CONFIG_FILE="$nonexistent_file"
firebreak_load_project_config
assert_eq "load_project_config succeeds when config file is absent" "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE" "env"

unset FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: lines without = are skipped
cat >"$config_file" <<'EOF'
AGENT_CONFIG=workspace
this-line-has-no-equals
FIREBREAK_VM_MODE=shell
EOF

unset AGENT_CONFIG FIREBREAK_VM_MODE 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config skips lines without equals sign" "${AGENT_CONFIG:-}" "workspace"
assert_eq "load_project_config continues after line without equals" "${FIREBREAK_VM_MODE:-}" "shell"

unset AGENT_CONFIG FIREBREAK_VM_MODE FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# Test: key with invalid characters is skipped
cat >"$config_file" <<'EOF'
AGENT CONFIG=workspace
AGENT_CONFIG=vm
EOF

unset AGENT_CONFIG 2>/dev/null || true
FIREBREAK_PROJECT_CONFIG_FILE="$config_file"
firebreak_load_project_config

assert_eq "load_project_config skips keys with spaces" "${AGENT_CONFIG:-}" "vm"

unset AGENT_CONFIG FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# ---------------------------------------------------------------------------
# firebreak_resolve_project_config_file with FIREBREAK_PROJECT_CONFIG_FILE
# ---------------------------------------------------------------------------

custom_config_path="$tmp_dir/custom.env"
touch "$custom_config_path"

firebreak_reset_project_config_state
FIREBREAK_PROJECT_CONFIG_FILE="$custom_config_path"
firebreak_resolve_project_config_file

assert_eq "resolve_project_config_file uses FIREBREAK_PROJECT_CONFIG_FILE env var" \
  "$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE" "$custom_config_path"
assert_eq "resolve_project_config_file sets source to env when using env override" \
  "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE" "env"

unset FIREBREAK_PROJECT_CONFIG_FILE 2>/dev/null || true

# ---------------------------------------------------------------------------
# firebreak_resolve_project_config_file with .firebreak.env in project root
# ---------------------------------------------------------------------------

project_dir="$tmp_dir/myproject"
mkdir -p "$project_dir"
cat >"$project_dir/.firebreak.env" <<'EOF'
AGENT_CONFIG=fresh
EOF

firebreak_reset_project_config_state
# Force the project root to our temp project dir (non-git)
FIREBREAK_RESOLVED_PROJECT_ROOT="$project_dir"
FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE="cwd"
firebreak_resolve_project_config_file

assert_eq "resolve_project_config_file finds .firebreak.env in project root" \
  "$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE" "$project_dir/.firebreak.env"
assert_eq "resolve_project_config_file sets source to project-default when file found" \
  "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE" "project-default"

# ---------------------------------------------------------------------------
# firebreak_resolve_project_config_file with no .firebreak.env
# ---------------------------------------------------------------------------

empty_project_dir="$tmp_dir/emptyproject"
mkdir -p "$empty_project_dir"

firebreak_reset_project_config_state
FIREBREAK_RESOLVED_PROJECT_ROOT="$empty_project_dir"
FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE="cwd"
firebreak_resolve_project_config_file

assert_eq "resolve_project_config_file returns candidate path even when no file exists" \
  "$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE" "$empty_project_dir/.firebreak.env"
assert_eq "resolve_project_config_file sets source to none when no file found" \
  "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE" "none"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf '%s\n' "Firebreak project-config unit tests passed"