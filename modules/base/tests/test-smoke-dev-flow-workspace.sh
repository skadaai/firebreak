set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

git_common_dir=$(git -C "$repo_root" rev-parse --git-common-dir)
if [ "$git_common_dir" != ".git" ]; then
  echo "run this task smoke from the primary checkout" >&2
  exit 1
fi

dev_flow_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak_dev-flow/tmp}
mkdir -p "$dev_flow_tmp_root"
workspace_tmp_dir=$(mktemp -d "$dev_flow_tmp_root/test-smoke-dev-flow-workspace.XXXXXX")
trap 'rm -rf "$workspace_tmp_dir"' EXIT INT TERM

state_dir=$workspace_tmp_dir/workspaces
workspace_root=$workspace_tmp_dir/checkouts
shared_root=$workspace_tmp_dir
run_flake=$repo_root/scripts/run-flake.sh
branch_suffix=$(basename "$workspace_tmp_dir" | tr '.' '-')

workspace_cmd() {
  DEV_FLOW_STATE_DIR="$state_dir" \
    DEV_FLOW_WORKSPACE_ROOT="$workspace_root" \
    DEV_FLOW_SHARED_ROOT="$shared_root" \
    FIREBREAK_TMPDIR="$workspace_tmp_dir/tmp" \
    bash "$run_flake" run .#dev-flow -- workspace "$@"
}

extract_json_field() {
  output=$1
  field=$2
  printf '%s\n' "$output" | sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

workspace_one_output=$(workspace_cmd create --workspace-id spec-005-main --branch "agent/spec-005-main-$branch_suffix" --owner smoke)
workspace_one_root=$(extract_json_field "$workspace_one_output" workspace_state_root)
workspace_one_path=$(extract_json_field "$workspace_one_output" workspace_path)
workspace_one_runtime_root=$(extract_json_field "$workspace_one_output" runtime_root)

if [ -z "$workspace_one_root" ] || ! [ -d "$workspace_one_root" ]; then
  printf '%s\n' "$workspace_one_output" >&2
  echo "workspace smoke did not create the first workspace state root" >&2
  exit 1
fi

if [ -z "$workspace_one_path" ] || ! [ -d "$workspace_one_path" ]; then
  printf '%s\n' "$workspace_one_output" >&2
  echo "workspace smoke did not create the first workspace checkout" >&2
  exit 1
fi

if ! [ -f "$workspace_one_root/metadata.json" ] || ! [ -d "$workspace_one_root/artifacts" ] || ! [ -d "$workspace_one_runtime_root" ]; then
  echo "workspace smoke did not create the expected first-workspace metadata layout" >&2
  exit 1
fi

set +e
workspace_cmd create --workspace-id spec-005-main --branch "agent/spec-005-main-$branch_suffix" --owner smoke >/dev/null 2>&1
duplicate_status=$?
set -e

if [ "$duplicate_status" -eq 0 ]; then
  echo "workspace smoke duplicate create did not fail deterministically" >&2
  exit 1
fi

resume_output=$(workspace_cmd create --workspace-id spec-005-main --branch "agent/spec-005-main-$branch_suffix" --owner smoke --resume)
resume_root=$(extract_json_field "$resume_output" workspace_state_root)
if [ "$resume_root" != "$workspace_one_root" ]; then
  printf '%s\n' "$resume_output" >&2
  echo "workspace smoke resume did not return the original workspace" >&2
  exit 1
fi

workspace_two_output=$(workspace_cmd create --workspace-id spec-006-main --branch "agent/spec-006-main-$branch_suffix" --owner smoke)
workspace_two_root=$(extract_json_field "$workspace_two_output" workspace_state_root)
workspace_two_path=$(extract_json_field "$workspace_two_output" workspace_path)
workspace_two_runtime_root=$(extract_json_field "$workspace_two_output" runtime_root)

if [ "$workspace_one_path" = "$workspace_two_path" ]; then
  echo "workspace smoke created colliding checkout paths" >&2
  exit 1
fi

if [ -z "$workspace_two_runtime_root" ] || [ "$workspace_one_runtime_root" = "$workspace_two_runtime_root" ]; then
  echo "workspace smoke created colliding runtime roots" >&2
  exit 1
fi

validation_suite=test-fixture-validation-pass
workspace_cmd validate --workspace-id spec-005-main "$validation_suite" >"$workspace_tmp_dir/workspace-one.validate.log" 2>&1 &
validate_one_pid=$!
workspace_cmd validate --workspace-id spec-006-main "$validation_suite" >"$workspace_tmp_dir/workspace-two.validate.log" 2>&1 &
validate_two_pid=$!

parallel_status=0
wait "$validate_one_pid" || parallel_status=$?
wait "$validate_two_pid" || parallel_status=$?

if [ "$parallel_status" -ne 0 ]; then
  echo "--- workspace one validate log ---" >&2
  sed -n '1,260p' "$workspace_tmp_dir/workspace-one.validate.log" >&2 || true
  echo "--- workspace two validate log ---" >&2
  sed -n '1,260p' "$workspace_tmp_dir/workspace-two.validate.log" >&2 || true
  echo "workspace smoke parallel validation failed" >&2
  exit "$parallel_status"
fi

if ! find "$workspace_one_root/validation/$validation_suite/runs" -name summary.json -print -quit | grep -q .; then
  echo "workspace smoke did not preserve validation evidence for workspace one" >&2
  exit 1
fi

if ! find "$workspace_two_root/validation/$validation_suite/runs" -name summary.json -print -quit | grep -q .; then
  echo "workspace smoke did not preserve validation evidence for workspace two" >&2
  exit 1
fi

if ! [ -f "$workspace_one_root/artifacts/latest-validation-$validation_suite.json" ] || ! [ -f "$workspace_two_root/artifacts/latest-validation-$validation_suite.json" ]; then
  echo "workspace smoke did not persist latest validation artifacts for both workspaces" >&2
  exit 1
fi

close_output=$(workspace_cmd close --workspace-id spec-005-main --disposition reviewed --cleanup-workspace)
if ! printf '%s\n' "$close_output" | grep -q '"status": "closed"'; then
  printf '%s\n' "$close_output" >&2
  echo "workspace smoke did not close the first workspace" >&2
  exit 1
fi

if [ -d "$workspace_one_path" ]; then
  echo "workspace smoke did not clean up the first workspace checkout" >&2
  exit 1
fi

if ! [ -f "$workspace_one_root/review/final-disposition.json" ]; then
  echo "workspace smoke did not preserve the final disposition record" >&2
  exit 1
fi

close_two_output=$(workspace_cmd close --workspace-id spec-006-main --disposition retained)
if ! printf '%s\n' "$close_two_output" | grep -q '"status": "closed"'; then
  printf '%s\n' "$close_two_output" >&2
  echo "workspace smoke did not close the second workspace" >&2
  exit 1
fi

printf '%s\n' "dev-flow workspace smoke test passed"
