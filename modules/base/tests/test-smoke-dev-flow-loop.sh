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

dev_flow_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak_dev-flow/tmp}
mkdir -p "$dev_flow_tmp_root"
loop_tmp_dir=$(mktemp -d "$dev_flow_tmp_root/test-smoke-dev-flow-loop.XXXXXX")
trap 'rm -rf "$loop_tmp_dir"' EXIT INT TERM
nix_config=$(
  cat <<EOF
${NIX_CONFIG:-}
max-jobs = 1
cores = 1
EOF
)

state_dir=$loop_tmp_dir/workspaces
workspace_root=$loop_tmp_dir/checkouts
shared_root=$loop_tmp_dir
run_flake=$repo_root/scripts/run-flake.sh
branch_suffix=$(basename "$loop_tmp_dir" | tr '.' '-')
spec_path=specs/006-bounded-autonomous-change-loop/SPEC.md

dev_flow_cmd() {
  DEV_FLOW_STATE_DIR="$state_dir" \
    DEV_FLOW_WORKSPACE_ROOT="$workspace_root" \
    DEV_FLOW_SHARED_ROOT="$shared_root" \
    FIREBREAK_TMPDIR="$loop_tmp_dir/tmp" \
    NIX_CONFIG="$nix_config" \
    bash "$run_flake" run .#dev-flow -- "$@"
}

extract_json_field() {
  output=$1
  field=$2
  printf '%s\n' "$output" | sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

close_workspace() {
  workspace_id=$1
  disposition=$2
  dev_flow_cmd workspace close --workspace-id "$workspace_id" --disposition "$disposition" --cleanup-workspace >/dev/null
}

success_branch="agent/spec-006-success-$branch_suffix"
success_validation_suite=test-fixture-validation-pass
success_output=$(dev_flow_cmd workspace create --workspace-id spec-006-success --branch "$success_branch" --owner smoke)
success_workspace=$(extract_json_field "$success_output" workspace_path)
printf '%s\n' '# loop smoke' >"$success_workspace/LOOP_SMOKE.md"
success_summary=$(dev_flow_cmd loop run \
  --workspace-id spec-006-success \
  --attempt-id success-run \
  --spec "$spec_path" \
  --plan "Add loop smoke artifact" \
  --validation-suite "$success_validation_suite" \
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
if ! [ -f "$success_plan_path" ] || ! [ -f "$success_review_path" ] || ! [ -f "$success_audit_root/policy.log" ] || ! [ -f "$success_audit_root/validation/$success_validation_suite.json" ]; then
  printf '%s\n' "$success_summary" >&2
  echo "loop smoke success scenario did not preserve the expected audit trail" >&2
  exit 1
fi
close_workspace spec-006-success committed

validation_branch="agent/spec-006-validation-$branch_suffix"
blocked_validation_suite=test-fixture-validation-blocked
validation_output=$(dev_flow_cmd workspace create --workspace-id spec-006-validation --branch "$validation_branch" --owner smoke)
validation_workspace=$(extract_json_field "$validation_output" workspace_path)
printf '%s\n' '# validation blocked' >"$validation_workspace/VALIDATION_BLOCKED.md"
set +e
validation_summary=$(dev_flow_cmd loop run \
  --workspace-id spec-006-validation \
  --attempt-id validation-blocked-run \
  --spec "$spec_path" \
  --plan "Exercise blocked validation path" \
  --validation-suite "$blocked_validation_suite" \
  --write-path .)
validation_status=$?
set -e
if [ "$validation_status" -eq 0 ] || ! printf '%s\n' "$validation_summary" | grep -q '"blocked_reason": "validation-blocked"'; then
  printf '%s\n' "$validation_summary" >&2
  echo "loop smoke validation-blocked scenario did not stop correctly" >&2
  exit 1
fi
validation_audit_root=$(extract_json_field "$validation_summary" audit_root)
validation_plan_path=$(extract_json_field "$validation_summary" plan_path)
if ! [ -f "$validation_plan_path" ] || ! [ -f "$validation_audit_root/validation/$blocked_validation_suite.json" ]; then
  printf '%s\n' "$validation_summary" >&2
  echo "loop smoke validation-blocked scenario did not preserve validation evidence" >&2
  exit 1
fi
close_workspace spec-006-validation blocked

policy_branch="agent/spec-006-policy-$branch_suffix"
dev_flow_cmd workspace create --workspace-id spec-006-policy --branch "$policy_branch" --owner smoke >/dev/null
set +e
policy_summary=$(
  dev_flow_cmd loop run \
    --workspace-id spec-006-policy \
    --attempt-id policy-blocked-run \
    --spec "$spec_path" \
    --plan "Exercise blocked policy path" \
    --validation-suite "$success_validation_suite" \
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
close_workspace spec-006-policy blocked

shared_escape_branch="agent/spec-006-shared-escape-$branch_suffix"
shared_escape_output=$(dev_flow_cmd workspace create --workspace-id spec-006-shared-escape --branch "$shared_escape_branch" --owner smoke)
shared_escape_workspace=$(extract_json_field "$shared_escape_output" workspace_path)
shared_escape_root=$loop_tmp_dir/shared-escape-root
mkdir -p "$shared_escape_root/probe"
rm "$shared_escape_workspace/.codex"
ln -s "$shared_escape_root" "$shared_escape_workspace/.codex"
printf '%s\n' 'escape' >"$shared_escape_workspace/.codex/probe/escape.txt"
set +e
shared_escape_summary=$(
  dev_flow_cmd loop run \
    --workspace-id spec-006-shared-escape \
    --attempt-id shared-escape-run \
    --spec "$spec_path" \
    --plan "Exercise managed shared-root boundary" \
    --validation-suite "$success_validation_suite" \
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
close_workspace spec-006-shared-escape blocked
runtime_branch="agent/spec-006-runtime-$branch_suffix"
dev_flow_cmd workspace create --workspace-id spec-006-runtime --branch "$runtime_branch" --owner smoke >/dev/null
set +e
runtime_summary=$(
  DEV_FLOW_MAX_RUNTIME_SECS=1 \
    dev_flow_cmd loop run \
      --workspace-id spec-006-runtime \
      --attempt-id runtime-blocked-run \
      --spec "$spec_path" \
      --plan "Exercise runtime limit path" \
      --validation-suite "$success_validation_suite" \
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
close_workspace spec-006-runtime blocked

parallel_branch="agent/spec-006-parallel-$branch_suffix"
dev_flow_cmd workspace create --workspace-id spec-006-parallel --branch "$parallel_branch" --owner smoke >/dev/null
set +e
parallel_summary=$(
  DEV_FLOW_MAX_PARALLELISM=0 \
    dev_flow_cmd loop run \
      --workspace-id spec-006-parallel \
      --attempt-id parallel-blocked-run \
      --spec "$spec_path" \
      --plan "Exercise parallelism limit path" \
      --validation-suite "$success_validation_suite" \
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
close_workspace spec-006-parallel blocked

printf '%s\n' "dev-flow loop smoke test passed"
