#!/usr/bin/env bash
# Unit tests for firebreak-doctor.sh helper functions.
# Tests source the helper libraries directly and exercise individual functions.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_CONFIG_LIB="$SCRIPT_DIR/../host/firebreak-project-config.sh"
DOCTOR_LIB="$SCRIPT_DIR/../host/firebreak-doctor.sh"

if ! [ -f "$PROJECT_CONFIG_LIB" ]; then
  echo "test-unit-doctor-helpers: cannot find firebreak-project-config.sh at $PROJECT_CONFIG_LIB" >&2
  exit 1
fi

if ! [ -f "$DOCTOR_LIB" ]; then
  echo "test-unit-doctor-helpers: cannot find firebreak-doctor.sh at $DOCTOR_LIB" >&2
  exit 1
fi

# shellcheck source=../host/firebreak-project-config.sh
. "$PROJECT_CONFIG_LIB"
# shellcheck source=../host/firebreak-doctor.sh
. "$DOCTOR_LIB"

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

# ---------------------------------------------------------------------------
# firebreak_doctor_resolve_host_dir
# ---------------------------------------------------------------------------

result=$(HOME="/home/testuser" firebreak_doctor_resolve_host_dir "~")
assert_eq "resolve_host_dir expands bare ~ to HOME" "$result" "/home/testuser"

result=$(HOME="/home/testuser" firebreak_doctor_resolve_host_dir "~/.codex")
assert_eq "resolve_host_dir expands ~/path to HOME/path" "$result" "/home/testuser/.codex"

result=$(HOME="/home/testuser" firebreak_doctor_resolve_host_dir "~/.config/firebreak")
assert_eq "resolve_host_dir expands ~/subdir/path" "$result" "/home/testuser/.config/firebreak"

result=$(HOME="/home/testuser" firebreak_doctor_resolve_host_dir "/absolute/path")
assert_eq "resolve_host_dir returns absolute path unchanged" "$result" "/absolute/path"

result=$(HOME="/home/testuser" firebreak_doctor_resolve_host_dir "relative/path")
assert_eq "resolve_host_dir returns relative path unchanged" "$result" "relative/path"

result=$(HOME="/home/testuser" firebreak_doctor_resolve_host_dir "/path/with/no/tilde")
assert_eq "resolve_host_dir handles path with no tilde" "$result" "/path/with/no/tilde"

# Edge case: HOME with trailing slash
result=$(HOME="/home/testuser/" firebreak_doctor_resolve_host_dir "~/.codex")
assert_eq "resolve_host_dir expands ~/path even when HOME has trailing slash" "$result" "/home/testuser//.codex"

# ---------------------------------------------------------------------------
# firebreak_doctor_primary_checkout_state
# ---------------------------------------------------------------------------

result=$(firebreak_doctor_primary_checkout_state ".git")
assert_eq "primary_checkout_state returns yes for .git" "$result" "yes"

result=$(firebreak_doctor_primary_checkout_state "")
assert_eq "primary_checkout_state returns unknown for empty string" "$result" "unknown"

result=$(firebreak_doctor_primary_checkout_state "/some/other/path/.git")
assert_eq "primary_checkout_state returns no for absolute path" "$result" "no"

result=$(firebreak_doctor_primary_checkout_state "worktrees/main/.git")
assert_eq "primary_checkout_state returns no for worktree path" "$result" "no"

result=$(firebreak_doctor_primary_checkout_state "../.git")
assert_eq "primary_checkout_state returns no for parent dir git" "$result" "no"

# ---------------------------------------------------------------------------
# firebreak_doctor_workspace_config_path
# ---------------------------------------------------------------------------

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

workspace_dir="$tmp_dir/workspace"
mkdir -p "$workspace_dir"

# Test with a regular (non-symlink) path
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_workspace_config_path ".codex")
  if [ "$result" != "$workspace_dir/.codex" ]; then
    echo "FAIL: workspace_config_path returns PWD/.codex for plain path" >&2
    echo "  expected: $workspace_dir/.codex" >&2
    echo "  actual:   $result" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

# Symlink tests require realpath; skip if unavailable
if command -v realpath >/dev/null 2>&1; then
  # Test with an actual symlink pointing inside the workspace
  mkdir -p "$workspace_dir/.codex-real"
  ln -s "$workspace_dir/.codex-real" "$workspace_dir/.codex-link"

  (
    cd "$workspace_dir"
    result=$(firebreak_doctor_workspace_config_path ".codex-link")
    # symlink target is inside PWD, so should return the candidate path
    if [ "$result" != "$workspace_dir/.codex-link" ]; then
      echo "FAIL: workspace_config_path returns candidate path for symlink inside workspace" >&2
      echo "  expected: $workspace_dir/.codex-link" >&2
      echo "  actual:   $result" >&2
      exit 1
    fi
  )
  pass_count=$((pass_count + 1))

  # Test with a symlink pointing outside the workspace
  outside_dir="$tmp_dir/outside"
  mkdir -p "$outside_dir/.claude-config"
  ln -s "$outside_dir/.claude-config" "$workspace_dir/.claude-link"

  (
    cd "$workspace_dir"
    result=$(firebreak_doctor_workspace_config_path ".claude-link")
    # symlink target is outside PWD, so should return the resolved target
    if [ "$result" != "$outside_dir/.claude-config" ]; then
      echo "FAIL: workspace_config_path returns resolved path for symlink outside workspace" >&2
      echo "  expected: $outside_dir/.claude-config" >&2
      echo "  actual:   $result" >&2
      exit 1
    fi
  )
  pass_count=$((pass_count + 1))
else
  echo "SKIP: symlink tests require realpath (not available in this environment)"
fi

# ---------------------------------------------------------------------------
# firebreak_doctor_resolve_agent_state
# ---------------------------------------------------------------------------

# Test: vm mode (default)
unset CODEX_CONFIG CODEX_CONFIG_HOST_PATH AGENT_CONFIG AGENT_CONFIG_HOST_PATH 2>/dev/null || true

(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  label=$(printf '%s' "$result" | cut -d'|' -f1)
  if [ "$label" != "codex" ] || [ "$mode" != "vm" ] || [ "$path" != "/var/lib/dev/.codex" ]; then
    echo "FAIL: resolve_agent_state defaults to vm mode for codex" >&2
    echo "  label=$label mode=$mode path=$path" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

# Test: agent-specific CODEX_CONFIG overrides generic AGENT_CONFIG
export AGENT_CONFIG=workspace
export CODEX_CONFIG=vm
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  if [ "$mode" != "vm" ]; then
    echo "FAIL: resolve_agent_state uses CODEX_CONFIG over AGENT_CONFIG" >&2
    echo "  mode=$mode (expected vm)" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset AGENT_CONFIG CODEX_CONFIG 2>/dev/null || true

# Test: workspace mode returns workspace config path
export CODEX_CONFIG=workspace
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  if [ "$mode" != "workspace" ]; then
    echo "FAIL: resolve_agent_state uses workspace mode when CODEX_CONFIG=workspace" >&2
    echo "  mode=$mode (expected workspace)" >&2
    exit 1
  fi
  if [ "$path" != "$workspace_dir/.codex" ]; then
    echo "FAIL: resolve_agent_state workspace path is PWD/.codex" >&2
    echo "  path=$path (expected $workspace_dir/.codex)" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset CODEX_CONFIG 2>/dev/null || true

# Test: host mode returns host path
export CODEX_CONFIG=host
export CODEX_CONFIG_HOST_PATH="/custom/codex/path"
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  if [ "$mode" != "host" ]; then
    echo "FAIL: resolve_agent_state uses host mode when CODEX_CONFIG=host" >&2
    echo "  mode=$mode (expected host)" >&2
    exit 1
  fi
  if [ "$path" != "/custom/codex/path" ]; then
    echo "FAIL: resolve_agent_state host path uses CODEX_CONFIG_HOST_PATH" >&2
    echo "  path=$path (expected /custom/codex/path)" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset CODEX_CONFIG CODEX_CONFIG_HOST_PATH 2>/dev/null || true

# Test: fresh mode returns /run/agent-config-fresh
export CODEX_CONFIG=fresh
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  if [ "$mode" != "fresh" ]; then
    echo "FAIL: resolve_agent_state uses fresh mode when CODEX_CONFIG=fresh" >&2
    echo "  mode=$mode (expected fresh)" >&2
    exit 1
  fi
  if [ "$path" != "/run/agent-config-fresh" ]; then
    echo "FAIL: resolve_agent_state fresh path is /run/agent-config-fresh" >&2
    echo "  path=$path (expected /run/agent-config-fresh)" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset CODEX_CONFIG 2>/dev/null || true

# Test: invalid mode is reported as invalid
export CODEX_CONFIG=bogusmode
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  if [ "$mode" != "invalid" ]; then
    echo "FAIL: resolve_agent_state reports invalid for unrecognized mode" >&2
    echo "  mode=$mode (expected invalid)" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset CODEX_CONFIG 2>/dev/null || true

# Test: Claude agent uses CLAUDE_* vars
export CLAUDE_CONFIG=vm
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "claude-code" "CLAUDE" "$HOME/.claude" ".claude")
  label=$(printf '%s' "$result" | cut -d'|' -f1)
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  if [ "$label" != "claude-code" ] || [ "$mode" != "vm" ] || [ "$path" != "/var/lib/dev/.claude" ]; then
    echo "FAIL: resolve_agent_state works for claude-code agent" >&2
    echo "  label=$label mode=$mode path=$path" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset CLAUDE_CONFIG 2>/dev/null || true

# Test: AGENT_CONFIG=host uses AGENT_CONFIG_HOST_PATH as fallback for host path
export AGENT_CONFIG=host
export AGENT_CONFIG_HOST_PATH="/shared/agent/config"
(
  cd "$workspace_dir"
  result=$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
  mode=$(printf '%s' "$result" | cut -d'|' -f2)
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  if [ "$mode" != "host" ] || [ "$path" != "/shared/agent/config" ]; then
    echo "FAIL: resolve_agent_state uses AGENT_CONFIG_HOST_PATH as generic fallback for host mode" >&2
    echo "  mode=$mode path=$path" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset AGENT_CONFIG AGENT_CONFIG_HOST_PATH 2>/dev/null || true

# Test: AGENT_CONFIG_HOST_PATH with tilde expansion
export AGENT_CONFIG=host
(
  cd "$workspace_dir"
  result=$(HOME="/home/testuser" AGENT_CONFIG_HOST_PATH="~/.config/shared" \
    firebreak_doctor_resolve_agent_state "codex" "CODEX" "~/.codex" ".codex")
  path=$(printf '%s' "$result" | cut -d'|' -f3)
  if [ "$path" != "/home/testuser/.config/shared" ]; then
    echo "FAIL: resolve_agent_state expands tilde in AGENT_CONFIG_HOST_PATH" >&2
    echo "  path=$path (expected /home/testuser/.config/shared)" >&2
    exit 1
  fi
)
pass_count=$((pass_count + 1))

unset AGENT_CONFIG 2>/dev/null || true

# ---------------------------------------------------------------------------
# firebreak_doctor_detect_kvm (test with fake /dev/kvm via env override)
# ---------------------------------------------------------------------------

# Create a fake readable+writable kvm device (regular file)
fake_kvm="$tmp_dir/fake_kvm"
touch "$fake_kvm"
chmod 666 "$fake_kvm"

result=$(
  bash -c "
    . '$PROJECT_CONFIG_LIB'
    . '$DOCTOR_LIB'
    # Override the path used in firebreak_doctor_detect_kvm by creating an alias
    # The function hardcodes /dev/kvm, so we test indirectly by checking its output
    firebreak_doctor_detect_kvm
  "
)
# We can't easily control /dev/kvm in tests, so just verify the function outputs one of the expected values
case "$result" in
  ok|missing|not-readable|not-writable)
    pass_count=$((pass_count + 1))
    ;;
  *)
    fail_count=$((fail_count + 1))
    echo "FAIL: detect_kvm returns unexpected value: $result" >&2
    ;;
esac

# ---------------------------------------------------------------------------
# firebreak_doctor_json_escape (if python3 is available)
# ---------------------------------------------------------------------------

if command -v python3 >/dev/null 2>&1; then
  result=$(firebreak_doctor_json_escape 'hello world')
  assert_eq "json_escape handles plain string" "$result" "hello world"

  result=$(firebreak_doctor_json_escape 'say "hello"')
  assert_eq "json_escape escapes double quotes" "$result" 'say \"hello\"'

  result=$(firebreak_doctor_json_escape 'path\with\backslash')
  assert_eq "json_escape escapes backslashes" "$result" 'path\\with\\backslash'

  result=$(firebreak_doctor_json_escape '')
  assert_eq "json_escape handles empty string" "$result" ""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $pass_count passed, $fail_count failed"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf '%s\n' "Firebreak doctor helper unit tests passed"