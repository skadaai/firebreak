set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

git_common_dir=$(git -C "$repo_root" rev-parse --git-common-dir)
if [ "$git_common_dir" != ".git" ]; then
  echo "run this session smoke from the primary checkout" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-/cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
session_tmp_dir=$(mktemp -d "$firebreak_tmp_root/session-smoke.XXXXXX")
trap 'rm -rf "$session_tmp_dir"' EXIT INT TERM

state_dir=$session_tmp_dir/sessions
worktree_root=$session_tmp_dir/worktrees
shared_root=$session_tmp_dir
run_flake=$repo_root/scripts/run-flake.sh
branch_suffix=$(basename "$session_tmp_dir" | tr '.' '-')

session_cmd() {
  FIREBREAK_SESSION_STATE_DIR="$state_dir" \
    FIREBREAK_WORKTREE_ROOT="$worktree_root" \
    FIREBREAK_WORKTREE_SHARED_ROOT="$shared_root" \
    FIREBREAK_TMPDIR="$session_tmp_dir/tmp" \
    bash "$run_flake" run .#firebreak -- session "$@"
}

extract_json_field() {
  output=$1
  field=$2
  printf '%s\n' "$output" | sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

session_one_output=$(session_cmd create --session-id session-one --branch "agent/spec-005-one-$branch_suffix" --owner smoke)
session_one_root=$(extract_json_field "$session_one_output" session_root)
session_one_worktree=$(extract_json_field "$session_one_output" worktree_path)
session_one_runtime_root=$(extract_json_field "$session_one_output" runtime_root)

if [ -z "$session_one_root" ] || ! [ -d "$session_one_root" ]; then
  printf '%s\n' "$session_one_output" >&2
  echo "session smoke did not create the first session root" >&2
  exit 1
fi

if [ -z "$session_one_worktree" ] || ! [ -d "$session_one_worktree" ]; then
  printf '%s\n' "$session_one_output" >&2
  echo "session smoke did not create the first session worktree" >&2
  exit 1
fi

if ! [ -f "$session_one_root/metadata.json" ] || ! [ -d "$session_one_root/artifacts" ] || ! [ -d "$session_one_runtime_root" ]; then
  echo "session smoke did not create the expected first-session metadata layout" >&2
  exit 1
fi

set +e
session_cmd create --session-id session-one --branch "agent/spec-005-one-$branch_suffix" --owner smoke >/dev/null 2>&1
duplicate_status=$?
set -e

if [ "$duplicate_status" -eq 0 ]; then
  echo "session smoke duplicate create did not fail deterministically" >&2
  exit 1
fi

resume_output=$(session_cmd create --session-id session-one --branch "agent/spec-005-one-$branch_suffix" --owner smoke --resume)
resume_root=$(extract_json_field "$resume_output" session_root)
if [ "$resume_root" != "$session_one_root" ]; then
  printf '%s\n' "$resume_output" >&2
  echo "session smoke resume did not return the original session" >&2
  exit 1
fi

session_two_output=$(session_cmd create --session-id session-two --branch "agent/spec-005-two-$branch_suffix" --owner smoke)
session_two_root=$(extract_json_field "$session_two_output" session_root)
session_two_worktree=$(extract_json_field "$session_two_output" worktree_path)
session_two_runtime_root=$(extract_json_field "$session_two_output" runtime_root)

if [ "$session_one_worktree" = "$session_two_worktree" ]; then
  echo "session smoke created colliding worktree paths" >&2
  exit 1
fi

if [ -z "$session_two_runtime_root" ] || [ "$session_one_runtime_root" = "$session_two_runtime_root" ]; then
  echo "session smoke created colliding runtime roots" >&2
  exit 1
fi

session_cmd validate --session-id session-one codex-version >"$session_tmp_dir/session-one.validate.log" 2>&1 &
validate_one_pid=$!
session_cmd validate --session-id session-two codex-version >"$session_tmp_dir/session-two.validate.log" 2>&1 &
validate_two_pid=$!

parallel_status=0
wait "$validate_one_pid" || parallel_status=$?
wait "$validate_two_pid" || parallel_status=$?

if [ "$parallel_status" -ne 0 ]; then
  echo "--- session one validate log ---" >&2
  sed -n '1,260p' "$session_tmp_dir/session-one.validate.log" >&2 || true
  echo "--- session two validate log ---" >&2
  sed -n '1,260p' "$session_tmp_dir/session-two.validate.log" >&2 || true
  echo "session smoke parallel validation failed" >&2
  exit "$parallel_status"
fi

if ! find "$session_one_root/validation/codex-version/runs" -name summary.json -print -quit | grep -q .; then
  echo "session smoke did not preserve validation evidence for session one" >&2
  exit 1
fi

if ! find "$session_two_root/validation/codex-version/runs" -name summary.json -print -quit | grep -q .; then
  echo "session smoke did not preserve validation evidence for session two" >&2
  exit 1
fi

if ! [ -f "$session_one_root/artifacts/latest-validation-codex-version.json" ] || ! [ -f "$session_two_root/artifacts/latest-validation-codex-version.json" ]; then
  echo "session smoke did not persist latest validation artifacts for both sessions" >&2
  exit 1
fi

close_output=$(session_cmd close --session-id session-one --disposition reviewed --cleanup-worktree)
if ! printf '%s\n' "$close_output" | grep -q '"status": "closed"'; then
  printf '%s\n' "$close_output" >&2
  echo "session smoke did not close the first session" >&2
  exit 1
fi

if [ -d "$session_one_worktree" ]; then
  echo "session smoke did not clean up the first session worktree" >&2
  exit 1
fi

if ! [ -f "$session_one_root/review/final-disposition.json" ]; then
  echo "session smoke did not preserve the final disposition record" >&2
  exit 1
fi

close_two_output=$(session_cmd close --session-id session-two --disposition retained)
if ! printf '%s\n' "$close_two_output" | grep -q '"status": "closed"'; then
  printf '%s\n' "$close_two_output" >&2
  echo "session smoke did not close the second session" >&2
  exit 1
fi

printf '%s\n' "Firebreak session smoke test passed"
