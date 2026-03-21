set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

git_common_dir=$(git -C "$repo_root" rev-parse --git-common-dir)
if [ "$git_common_dir" != ".git" ]; then
  echo "run this autonomy smoke from the primary checkout" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-/cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
autonomy_tmp_dir=$(mktemp -d "$firebreak_tmp_root/autonomy-smoke.XXXXXX")
trap 'rm -rf "$autonomy_tmp_dir"' EXIT INT TERM

state_dir=$autonomy_tmp_dir/sessions
worktree_root=$autonomy_tmp_dir/worktrees
shared_root=$autonomy_tmp_dir
run_flake=$repo_root/scripts/run-flake.sh
branch_suffix=$(basename "$autonomy_tmp_dir" | tr '.' '-')
spec_path=specs/006-bounded-autonomous-change-loop/SPEC.md

firebreak_cmd() {
  FIREBREAK_SESSION_STATE_DIR="$state_dir" \
    FIREBREAK_WORKTREE_ROOT="$worktree_root" \
    FIREBREAK_WORKTREE_SHARED_ROOT="$shared_root" \
    FIREBREAK_TMPDIR="$autonomy_tmp_dir/tmp" \
    bash "$run_flake" run .#firebreak -- "$@"
}

extract_json_field() {
  output=$1
  field=$2
  printf '%s\n' "$output" | sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

close_session() {
  session_id=$1
  disposition=$2
  firebreak_cmd session close --session-id "$session_id" --disposition "$disposition" --cleanup-worktree >/dev/null
}

success_branch="agent/spec-006-success-$branch_suffix"
success_output=$(firebreak_cmd session create --session-id success --branch "$success_branch" --owner smoke)
success_worktree=$(extract_json_field "$success_output" worktree_path)
printf '%s\n' '# autonomy smoke' >"$success_worktree/AUTONOMY_SMOKE.md"
success_summary=$(firebreak_cmd autonomy run \
  --session-id success \
  --attempt-id success-run \
  --spec "$spec_path" \
  --plan "Add autonomy smoke artifact" \
  --validation-suite codex-version \
  --write-path . \
  --commit-message "autonomy smoke commit")
if ! printf '%s\n' "$success_summary" | grep -q '"result": "completed"'; then
  printf '%s\n' "$success_summary" >&2
  echo "autonomy smoke success scenario did not complete" >&2
  exit 1
fi
success_commit=$(extract_json_field "$success_summary" commit_sha)
if [ -z "$success_commit" ]; then
  printf '%s\n' "$success_summary" >&2
  echo "autonomy smoke success scenario did not record a commit" >&2
  exit 1
fi
success_audit_root=$(extract_json_field "$success_summary" audit_root)
success_plan_path=$(extract_json_field "$success_summary" plan_path)
success_review_path=$(extract_json_field "$success_summary" review_path)
if ! [ -f "$success_plan_path" ] || ! [ -f "$success_review_path" ] || ! [ -f "$success_audit_root/policy.log" ] || ! [ -f "$success_audit_root/validation/codex-version.json" ]; then
  printf '%s\n' "$success_summary" >&2
  echo "autonomy smoke success scenario did not preserve the expected audit trail" >&2
  exit 1
fi
close_session success committed

validation_branch="agent/spec-006-validation-$branch_suffix"
validation_output=$(firebreak_cmd session create --session-id validation-blocked --branch "$validation_branch" --owner smoke)
validation_worktree=$(extract_json_field "$validation_output" worktree_path)
printf '%s\n' '# validation blocked' >"$validation_worktree/VALIDATION_BLOCKED.md"
set +e
validation_summary=$(
  FIREBREAK_VALIDATION_FORCE_BLOCKED_REASON="smoke-blocked" \
    firebreak_cmd autonomy run \
      --session-id validation-blocked \
      --attempt-id validation-blocked-run \
      --spec "$spec_path" \
      --plan "Exercise blocked validation path" \
      --validation-suite codex-version \
      --write-path .
)
validation_status=$?
set -e
if [ "$validation_status" -eq 0 ] || ! printf '%s\n' "$validation_summary" | grep -q '"blocked_reason": "validation-blocked"'; then
  printf '%s\n' "$validation_summary" >&2
  echo "autonomy smoke validation-blocked scenario did not stop correctly" >&2
  exit 1
fi
validation_audit_root=$(extract_json_field "$validation_summary" audit_root)
validation_plan_path=$(extract_json_field "$validation_summary" plan_path)
if ! [ -f "$validation_plan_path" ] || ! [ -f "$validation_audit_root/validation/codex-version.json" ]; then
  printf '%s\n' "$validation_summary" >&2
  echo "autonomy smoke validation-blocked scenario did not preserve validation evidence" >&2
  exit 1
fi
close_session validation-blocked blocked

policy_branch="agent/spec-006-policy-$branch_suffix"
firebreak_cmd session create --session-id policy-blocked --branch "$policy_branch" --owner smoke >/dev/null
set +e
policy_summary=$(
  firebreak_cmd autonomy run \
    --session-id policy-blocked \
    --attempt-id policy-blocked-run \
    --spec "$spec_path" \
    --plan "Exercise blocked policy path" \
    --validation-suite codex-version \
    --write-path ../escape.txt
)
policy_status=$?
set -e
if [ "$policy_status" -eq 0 ] || ! printf '%s\n' "$policy_summary" | grep -q '"blocked_reason": "policy-write-scope"'; then
  printf '%s\n' "$policy_summary" >&2
  echo "autonomy smoke policy-blocked scenario did not stop correctly" >&2
  exit 1
fi
policy_audit_root=$(extract_json_field "$policy_summary" audit_root)
policy_plan_path=$(extract_json_field "$policy_summary" plan_path)
if ! [ -f "$policy_plan_path" ] || ! [ -f "$policy_audit_root/policy.log" ]; then
  printf '%s\n' "$policy_summary" >&2
  echo "autonomy smoke policy-blocked scenario did not preserve policy evidence" >&2
  exit 1
fi
close_session policy-blocked blocked

printf '%s\n' "Firebreak autonomy smoke test passed"
