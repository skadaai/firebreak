set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

git_common_dir=$(git -C "$repo_root" rev-parse --git-common-dir)
if [ "$git_common_dir" != ".git" ]; then
  echo "run this loop smoke from the primary checkout" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-/cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
loop_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-internal-loop.XXXXXX")
trap 'rm -rf "$loop_tmp_dir"' EXIT INT TERM

state_dir=$loop_tmp_dir/tasks
worktree_root=$loop_tmp_dir/worktrees
shared_root=$loop_tmp_dir
run_flake=$repo_root/scripts/run-flake.sh
branch_suffix=$(basename "$loop_tmp_dir" | tr '.' '-')
spec_path=specs/006-bounded-autonomous-change-loop/SPEC.md

firebreak_cmd() {
  FIREBREAK_TASK_STATE_DIR="$state_dir" \
    FIREBREAK_TASK_WORKTREE_ROOT="$worktree_root" \
    FIREBREAK_TASK_SHARED_ROOT="$shared_root" \
    FIREBREAK_TMPDIR="$loop_tmp_dir/tmp" \
    bash "$run_flake" run .#firebreak -- "$@"
}

extract_json_field() {
  output=$1
  field=$2
  printf '%s\n' "$output" | sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

close_task() {
  task_id=$1
  disposition=$2
  firebreak_cmd internal task close --task-id "$task_id" --disposition "$disposition" --cleanup-worktree >/dev/null
}

success_branch="agent/spec-006-success-$branch_suffix"
success_output=$(firebreak_cmd internal task create --task-id success --branch "$success_branch" --owner smoke)
success_worktree=$(extract_json_field "$success_output" worktree_path)
printf '%s\n' '# loop smoke' >"$success_worktree/LOOP_SMOKE.md"
success_summary=$(firebreak_cmd internal loop run \
  --task-id success \
  --attempt-id success-run \
  --spec "$spec_path" \
  --plan "Add loop smoke artifact" \
  --validation-suite test-smoke-codex-version \
  --write-path . \
  --commit-message "loop smoke commit")
if ! printf '%s\n' "$success_summary" | grep -q '"result": "completed"'; then
  printf '%s\n' "$success_summary" >&2
  echo "loop smoke success scenario did not complete" >&2
  exit 1
fi
success_commit=$(extract_json_field "$success_summary" commit_sha)
if [ -z "$success_commit" ]; then
  printf '%s\n' "$success_summary" >&2
  echo "loop smoke success scenario did not record a commit" >&2
  exit 1
fi
success_audit_root=$(extract_json_field "$success_summary" audit_root)
success_plan_path=$(extract_json_field "$success_summary" plan_path)
success_review_path=$(extract_json_field "$success_summary" review_path)
if ! [ -f "$success_plan_path" ] || ! [ -f "$success_review_path" ] || ! [ -f "$success_audit_root/policy.log" ] || ! [ -f "$success_audit_root/validation/test-smoke-codex-version.json" ]; then
  printf '%s\n' "$success_summary" >&2
  echo "loop smoke success scenario did not preserve the expected audit trail" >&2
  exit 1
fi
close_task success committed

validation_branch="agent/spec-006-validation-$branch_suffix"
validation_output=$(firebreak_cmd internal task create --task-id validation-blocked --branch "$validation_branch" --owner smoke)
validation_worktree=$(extract_json_field "$validation_output" worktree_path)
printf '%s\n' '# validation blocked' >"$validation_worktree/VALIDATION_BLOCKED.md"
set +e
validation_summary=$(
  FIREBREAK_VALIDATION_FORCE_BLOCKED_REASON="smoke-blocked" \
    firebreak_cmd internal loop run \
      --task-id validation-blocked \
      --attempt-id validation-blocked-run \
      --spec "$spec_path" \
      --plan "Exercise blocked validation path" \
      --validation-suite test-smoke-codex-version \
      --write-path .
)
validation_status=$?
set -e
if [ "$validation_status" -eq 0 ] || ! printf '%s\n' "$validation_summary" | grep -q '"blocked_reason": "validation-blocked"'; then
  printf '%s\n' "$validation_summary" >&2
  echo "loop smoke validation-blocked scenario did not stop correctly" >&2
  exit 1
fi
validation_audit_root=$(extract_json_field "$validation_summary" audit_root)
validation_plan_path=$(extract_json_field "$validation_summary" plan_path)
if ! [ -f "$validation_plan_path" ] || ! [ -f "$validation_audit_root/validation/test-smoke-codex-version.json" ]; then
  printf '%s\n' "$validation_summary" >&2
  echo "loop smoke validation-blocked scenario did not preserve validation evidence" >&2
  exit 1
fi
close_task validation-blocked blocked

policy_branch="agent/spec-006-policy-$branch_suffix"
firebreak_cmd internal task create --task-id policy-blocked --branch "$policy_branch" --owner smoke >/dev/null
set +e
policy_summary=$(
  firebreak_cmd internal loop run \
    --task-id policy-blocked \
    --attempt-id policy-blocked-run \
    --spec "$spec_path" \
    --plan "Exercise blocked policy path" \
    --validation-suite test-smoke-codex-version \
    --write-path ../escape.txt
)
policy_status=$?
set -e
if [ "$policy_status" -eq 0 ] || ! printf '%s\n' "$policy_summary" | grep -q '"blocked_reason": "policy-write-scope"'; then
  printf '%s\n' "$policy_summary" >&2
  echo "loop smoke policy-blocked scenario did not stop correctly" >&2
  exit 1
fi
policy_audit_root=$(extract_json_field "$policy_summary" audit_root)
policy_plan_path=$(extract_json_field "$policy_summary" plan_path)
if ! [ -f "$policy_plan_path" ] || ! [ -f "$policy_audit_root/policy.log" ]; then
  printf '%s\n' "$policy_summary" >&2
  echo "loop smoke policy-blocked scenario did not preserve policy evidence" >&2
  exit 1
fi
close_task policy-blocked blocked

shared_escape_branch="agent/spec-006-shared-escape-$branch_suffix"
shared_escape_output=$(firebreak_cmd internal task create --task-id shared-escape --branch "$shared_escape_branch" --owner smoke)
shared_escape_worktree=$(extract_json_field "$shared_escape_output" worktree_path)
shared_escape_root=$loop_tmp_dir/shared-escape-root
mkdir -p "$shared_escape_root/probe"
rm "$shared_escape_worktree/.codex"
ln -s "$shared_escape_root" "$shared_escape_worktree/.codex"
printf '%s\n' 'escape' >"$shared_escape_worktree/.codex/probe/escape.txt"
set +e
shared_escape_summary=$(
  firebreak_cmd internal loop run \
    --task-id shared-escape \
    --attempt-id shared-escape-run \
    --spec "$spec_path" \
    --plan "Exercise managed shared-root boundary" \
    --validation-suite test-smoke-codex-version \
    --write-path .
)
shared_escape_status=$?
set -e
if [ "$shared_escape_status" -eq 0 ] || ! printf '%s\n' "$shared_escape_summary" | grep -q '"blocked_reason": "policy-write-scope"'; then
  printf '%s\n' "$shared_escape_summary" >&2
  echo "loop smoke shared-escape scenario did not stop correctly" >&2
  exit 1
fi
shared_escape_audit_root=$(extract_json_field "$shared_escape_summary" audit_root)
shared_escape_plan_path=$(extract_json_field "$shared_escape_summary" plan_path)
if ! [ -f "$shared_escape_plan_path" ] || ! [ -f "$shared_escape_audit_root/review/write-scope.log" ] || ! grep -q '^.codex' "$shared_escape_audit_root/review/write-scope.log"; then
  printf '%s\n' "$shared_escape_summary" >&2
  echo "loop smoke shared-escape scenario did not preserve write-scope evidence" >&2
  exit 1
fi
close_task shared-escape blocked

runtime_branch="agent/spec-006-runtime-$branch_suffix"
firebreak_cmd internal task create --task-id runtime-blocked --branch "$runtime_branch" --owner smoke >/dev/null
set +e
runtime_summary=$(
  FIREBREAK_LOOP_MAX_RUNTIME_SECS=1 \
    firebreak_cmd internal loop run \
      --task-id runtime-blocked \
      --attempt-id runtime-blocked-run \
      --spec "$spec_path" \
      --plan "Exercise runtime limit path" \
      --validation-suite test-smoke-codex-version \
      --write-path .
)
runtime_status=$?
set -e
if [ "$runtime_status" -eq 0 ] || ! printf '%s\n' "$runtime_summary" | grep -q '"blocked_reason": "policy-runtime-limit"'; then
  printf '%s\n' "$runtime_summary" >&2
  echo "loop smoke runtime-blocked scenario did not stop correctly" >&2
  exit 1
fi
runtime_audit_root=$(extract_json_field "$runtime_summary" audit_root)
runtime_plan_path=$(extract_json_field "$runtime_summary" plan_path)
if ! [ -f "$runtime_plan_path" ] || ! [ -f "$runtime_audit_root/summary.json" ]; then
  printf '%s\n' "$runtime_summary" >&2
  echo "loop smoke runtime-blocked scenario did not preserve runtime evidence" >&2
  exit 1
fi
close_task runtime-blocked blocked

parallel_branch="agent/spec-006-parallel-$branch_suffix"
firebreak_cmd internal task create --task-id parallel-blocked --branch "$parallel_branch" --owner smoke >/dev/null
set +e
parallel_summary=$(
  FIREBREAK_LOOP_MAX_PARALLELISM=0 \
    firebreak_cmd internal loop run \
      --task-id parallel-blocked \
      --attempt-id parallel-blocked-run \
      --spec "$spec_path" \
      --plan "Exercise parallelism limit path" \
      --validation-suite test-smoke-codex-version \
      --write-path .
)
parallel_status=$?
set -e
if [ "$parallel_status" -eq 0 ] || ! printf '%s\n' "$parallel_summary" | grep -q '"blocked_reason": "policy-parallelism-limit"'; then
  printf '%s\n' "$parallel_summary" >&2
  echo "loop smoke parallelism-blocked scenario did not stop correctly" >&2
  exit 1
fi
parallel_audit_root=$(extract_json_field "$parallel_summary" audit_root)
parallel_plan_path=$(extract_json_field "$parallel_summary" plan_path)
if ! [ -f "$parallel_plan_path" ] || ! [ -f "$parallel_audit_root/policy.log" ]; then
  printf '%s\n' "$parallel_summary" >&2
  echo "loop smoke parallelism-blocked scenario did not preserve policy evidence" >&2
  exit 1
fi
close_task parallel-blocked blocked

printf '%s\n' "Firebreak internal loop smoke test passed"
