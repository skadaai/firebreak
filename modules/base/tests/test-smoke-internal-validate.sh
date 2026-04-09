set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
state_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-internal-validate-state.XXXXXX")
blocked_state_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-internal-validate-blocked.XXXXXX")
trap 'rm -rf "$state_dir" "$blocked_state_dir"' EXIT INT TERM

validation_cmd() {
  @VALIDATE_BIN@ run --state-dir "$state_dir" "$@"
}

summary_output=$(validation_cmd test-fixture-validation-pass)

summary_path=$(printf '%s\n' "$summary_output" | sed -n 's/.*"run_dir": "\([^"]*\)".*/\1\/summary.json/p' | head -n 1)
if [ -z "$summary_path" ] || ! [ -f "$summary_path" ]; then
  printf '%s\n' "$summary_output" >&2
  echo "validation smoke did not produce a summary path for the success case" >&2
  exit 1
fi

if ! grep -q '"result": "passed"' "$summary_path"; then
  cat "$summary_path" >&2
  echo "validation smoke did not report a passing success case" >&2
  exit 1
fi

if ! grep -q '"stdout_path": "' "$summary_path"; then
  cat "$summary_path" >&2
  echo "validation smoke summary did not include artifact paths" >&2
  exit 1
fi

blocked_output=$(FIREBREAK_VALIDATION_STATE_DIR="$blocked_state_dir" @VALIDATE_BIN@ run test-fixture-validation-blocked)

blocked_summary_path=$(printf '%s\n' "$blocked_output" | sed -n 's/.*"run_dir": "\([^"]*\)".*/\1\/summary.json/p' | head -n 1)
if [ -z "$blocked_summary_path" ] || ! [ -f "$blocked_summary_path" ]; then
  printf '%s\n' "$blocked_output" >&2
  echo "validation smoke did not produce a summary path for the blocked case" >&2
  exit 1
fi

if ! grep -q '"result": "blocked"' "$blocked_summary_path"; then
  cat "$blocked_summary_path" >&2
  echo "validation smoke did not report a blocked case" >&2
  exit 1
fi

if ! grep -q '"missing_capability": "validation-fixture-blocked"' "$blocked_summary_path"; then
  cat "$blocked_summary_path" >&2
  echo "validation smoke did not preserve the blocked reason" >&2
  exit 1
fi

printf '%s\n' "Firebreak internal validate smoke test passed"
