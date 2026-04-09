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

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
task_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-internal-task.XXXXXX")
trap 'rm -rf "$task_tmp_dir"' EXIT INT TERM
nix_config=$(
  cat <<EOF
${NIX_CONFIG:-}
max-jobs = 1
cores = 1
EOF
)

state_dir=$task_tmp_dir/tasks
worktree_root=$task_tmp_dir/worktrees
shared_root=$task_tmp_dir
run_flake=$repo_root/scripts/run-flake.sh
branch_suffix=$(basename "$task_tmp_dir" | tr '.' '-')

task_cmd() {
  FIREBREAK_TASK_STATE_DIR="$state_dir" \
    FIREBREAK_TASK_WORKTREE_ROOT="$worktree_root" \
    FIREBREAK_TASK_SHARED_ROOT="$shared_root" \
    FIREBREAK_TMPDIR="$task_tmp_dir/tmp" \
    NIX_CONFIG="$nix_config" \
    bash "$run_flake" run .#firebreak -- internal task "$@"
}

extract_json_field() {
  output=$1
  field=$2
  printf '%s\n' "$output" | sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

task_one_output=$(task_cmd create --task-id task-one --branch "agent/spec-005-one-$branch_suffix" --owner smoke)
task_one_root=$(extract_json_field "$task_one_output" task_root)
task_one_worktree=$(extract_json_field "$task_one_output" worktree_path)
task_one_runtime_root=$(extract_json_field "$task_one_output" runtime_root)

if [ -z "$task_one_root" ] || ! [ -d "$task_one_root" ]; then
  printf '%s\n' "$task_one_output" >&2
  echo "task smoke did not create the first task root" >&2
  exit 1
fi

if [ -z "$task_one_worktree" ] || ! [ -d "$task_one_worktree" ]; then
  printf '%s\n' "$task_one_output" >&2
  echo "task smoke did not create the first task worktree" >&2
  exit 1
fi

if ! [ -f "$task_one_root/metadata.json" ] || ! [ -d "$task_one_root/artifacts" ] || ! [ -d "$task_one_runtime_root" ]; then
  echo "task smoke did not create the expected first-task metadata layout" >&2
  exit 1
fi

set +e
task_cmd create --task-id task-one --branch "agent/spec-005-one-$branch_suffix" --owner smoke >/dev/null 2>&1
duplicate_status=$?
set -e

if [ "$duplicate_status" -eq 0 ]; then
  echo "task smoke duplicate create did not fail deterministically" >&2
  exit 1
fi

resume_output=$(task_cmd create --task-id task-one --branch "agent/spec-005-one-$branch_suffix" --owner smoke --resume)
resume_root=$(extract_json_field "$resume_output" task_root)
if [ "$resume_root" != "$task_one_root" ]; then
  printf '%s\n' "$resume_output" >&2
  echo "task smoke resume did not return the original task" >&2
  exit 1
fi

task_two_output=$(task_cmd create --task-id task-two --branch "agent/spec-005-two-$branch_suffix" --owner smoke)
task_two_root=$(extract_json_field "$task_two_output" task_root)
task_two_worktree=$(extract_json_field "$task_two_output" worktree_path)
task_two_runtime_root=$(extract_json_field "$task_two_output" runtime_root)

if [ "$task_one_worktree" = "$task_two_worktree" ]; then
  echo "task smoke created colliding worktree paths" >&2
  exit 1
fi

if [ -z "$task_two_runtime_root" ] || [ "$task_one_runtime_root" = "$task_two_runtime_root" ]; then
  echo "task smoke created colliding runtime roots" >&2
  exit 1
fi

validation_suite=test-fixture-validation-pass

task_cmd validate --task-id task-one "$validation_suite" >"$task_tmp_dir/task-one.validate.log" 2>&1 || validation_status=$?
: "${validation_status:=0}"
if [ "$validation_status" -eq 0 ]; then
  task_cmd validate --task-id task-two "$validation_suite" >"$task_tmp_dir/task-two.validate.log" 2>&1 || validation_status=$?
fi

if [ "$validation_status" -ne 0 ]; then
  echo "--- task one validate log ---" >&2
  sed -n '1,260p' "$task_tmp_dir/task-one.validate.log" >&2 || true
  echo "--- task two validate log ---" >&2
  sed -n '1,260p' "$task_tmp_dir/task-two.validate.log" >&2 || true
  echo "task smoke validation failed" >&2
  exit "$validation_status"
fi

if ! find "$task_one_root/validation/$validation_suite/runs" -name summary.json -print -quit | grep -q .; then
  echo "task smoke did not preserve validation evidence for task one" >&2
  exit 1
fi

if ! find "$task_two_root/validation/$validation_suite/runs" -name summary.json -print -quit | grep -q .; then
  echo "task smoke did not preserve validation evidence for task two" >&2
  exit 1
fi

if ! [ -f "$task_one_root/artifacts/latest-validation-${validation_suite}.json" ] || ! [ -f "$task_two_root/artifacts/latest-validation-${validation_suite}.json" ]; then
  echo "task smoke did not persist latest validation artifacts for both tasks" >&2
  exit 1
fi

close_output=$(task_cmd close --task-id task-one --disposition reviewed --cleanup-worktree)
if ! printf '%s\n' "$close_output" | grep -q '"status": "closed"'; then
  printf '%s\n' "$close_output" >&2
  echo "task smoke did not close the first task" >&2
  exit 1
fi

if [ -d "$task_one_worktree" ]; then
  echo "task smoke did not clean up the first task worktree" >&2
  exit 1
fi

if ! [ -f "$task_one_root/review/final-disposition.json" ]; then
  echo "task smoke did not preserve the final disposition record" >&2
  exit 1
fi

close_two_output=$(task_cmd close --task-id task-two --disposition retained)
if ! printf '%s\n' "$close_two_output" | grep -q '"status": "closed"'; then
  printf '%s\n' "$close_two_output" >&2
  echo "task smoke did not close the second task" >&2
  exit 1
fi

printf '%s\n' "Firebreak internal task smoke test passed"
