set -eu

state_dir=${FIREBREAK_TASK_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/tasks}
worktree_root=${FIREBREAK_TASK_WORKTREE_ROOT:-$state_dir/worktrees}
shared_root=${FIREBREAK_TASK_SHARED_ROOT:-$(dirname "$worktree_root")}
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak internal task create --task-id ID --branch BRANCH [--owner NAME] [--base-ref REF] [--resume]
  firebreak internal task show --task-id ID
  firebreak internal task validate --task-id ID SUITE
  firebreak internal task close --task-id ID --disposition VALUE [--cleanup-worktree]
EOF
  exit 1
}

json_escape() {
  value=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  value=$(printf '%s' "$value" | tr '\n' ' ')
  printf '%s' "$value"
}

validate_task_id() {
  case "$1" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "task id must be a single path-safe token without whitespace: $1" >&2
      exit 1
      ;;
  esac
}

validate_suite_name() {
  case "$1" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "suite name must be a single path-safe token without whitespace: $1" >&2
      exit 1
      ;;
  esac
}

require_absolute_dir() {
  value=$1
  description=$2
  case "$value" in
    /*) ;;
    *)
      echo "$description must be absolute: $value" >&2
      exit 1
      ;;
  esac
}

require_primary_checkout() {
  repo_root=$1
  git_common_dir=$(git -C "$repo_root" rev-parse --git-common-dir)
  if [ "$git_common_dir" != ".git" ]; then
    echo "task creation must run from the primary checkout: $repo_root" >&2
    echo "current git-common-dir: $git_common_dir" >&2
    exit 1
  fi
}

resolve_task_base_ref() {
  repo_root=$1

  if [ -n "${FIREBREAK_TASK_BASE_REF:-}" ]; then
    printf '%s\n' "$FIREBREAK_TASK_BASE_REF"
    return
  fi

  current_branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [ -n "$current_branch" ]; then
    printf '%s\n' "$current_branch"
    return
  fi

  printf '%s\n' HEAD
}

sync_primary_checkout_to_worktree() {
  repo_root=$1
  target_worktree=$2

  (
    cd "$repo_root"

    git ls-files --deleted -z |
      while IFS= read -r -d '' path; do
        rm -f "$target_worktree/$path"
      done

    git ls-files --cached --modified --others --exclude-standard -z |
      while IFS= read -r -d '' path; do
        case "$path" in
          .direnv|.direnv/*|.agent-sandbox.env|result|result/*|*.img|*.socket)
            continue
            ;;
        esac

        mkdir -p "$(dirname "$target_worktree/$path")"
        cp -a "$path" "$target_worktree/$path"
      done
  )
}

load_task() {
  task_id=$1
  validate_task_id "$task_id"
  task_root=$state_dir/$task_id
  metadata_path=$task_root/metadata.json

  if ! [ -f "$metadata_path" ]; then
    echo "unknown task id: $task_id" >&2
    exit 1
  fi

  branch=$(cat "$task_root/branch")
  owner=$(cat "$task_root/owner")
  primary_checkout=$(cat "$task_root/primary-checkout")
  worktree_path=$(cat "$task_root/worktree-path")
  worktree_shared_root=$(cat "$task_root/worktree-shared-root")
  validation_root=$(cat "$task_root/validation-root")
  runtime_root=$(cat "$task_root/runtime-root")
  vm_state_root=$(cat "$task_root/vm-state-root")
  artifact_root=$(cat "$task_root/artifact-root")
  tmp_root=$(cat "$task_root/tmp-root")
  cloud_state_root=$(cat "$task_root/cloud-state-root")
  created_at=$(cat "$task_root/created-at")
  status=$(cat "$task_root/status")
  disposition=""
  closed_at=""
  if [ -f "$task_root/disposition" ]; then
    disposition=$(cat "$task_root/disposition")
  fi
  if [ -f "$task_root/closed-at" ]; then
    closed_at=$(cat "$task_root/closed-at")
  fi
}

write_metadata() {
  mkdir -p "$task_root" "$validation_root" "$runtime_root" "$vm_state_root" "$artifact_root" "$tmp_root" "$cloud_state_root" "$task_root/review"
  printf '%s\n' "$task_id" >"$task_root/task-id"
  printf '%s\n' "$branch" >"$task_root/branch"
  printf '%s\n' "$owner" >"$task_root/owner"
  printf '%s\n' "$primary_checkout" >"$task_root/primary-checkout"
  printf '%s\n' "$worktree_path" >"$task_root/worktree-path"
  printf '%s\n' "$worktree_shared_root" >"$task_root/worktree-shared-root"
  printf '%s\n' "$validation_root" >"$task_root/validation-root"
  printf '%s\n' "$runtime_root" >"$task_root/runtime-root"
  printf '%s\n' "$vm_state_root" >"$task_root/vm-state-root"
  printf '%s\n' "$artifact_root" >"$task_root/artifact-root"
  printf '%s\n' "$tmp_root" >"$task_root/tmp-root"
  printf '%s\n' "$cloud_state_root" >"$task_root/cloud-state-root"
  printf '%s\n' "$created_at" >"$task_root/created-at"
  printf '%s\n' "$status" >"$task_root/status"
  if [ -n "$disposition" ]; then
    printf '%s\n' "$disposition" >"$task_root/disposition"
  else
    rm -f "$task_root/disposition"
  fi
  if [ -n "$closed_at" ]; then
    printf '%s\n' "$closed_at" >"$task_root/closed-at"
  else
    rm -f "$task_root/closed-at"
  fi

  cat >"$metadata_path" <<EOF
{
  "task_id": "$(json_escape "$task_id")",
  "status": "$(json_escape "$status")",
  "owner": "$(json_escape "$owner")",
  "branch": "$(json_escape "$branch")",
  "primary_checkout": "$(json_escape "$primary_checkout")",
  "worktree_path": "$(json_escape "$worktree_path")",
  "worktree_shared_root": "$(json_escape "$worktree_shared_root")",
  "task_root": "$(json_escape "$task_root")",
  "validation_root": "$(json_escape "$validation_root")",
  "runtime_root": "$(json_escape "$runtime_root")",
  "vm_state_root": "$(json_escape "$vm_state_root")",
  "artifact_root": "$(json_escape "$artifact_root")",
  "tmp_root": "$(json_escape "$tmp_root")",
  "cloud_state_root": "$(json_escape "$cloud_state_root")",
  "created_at": "$(json_escape "$created_at")",
  "closed_at": $(if [ -n "$closed_at" ]; then printf '"%s"' "$(json_escape "$closed_at")"; else printf 'null'; fi),
  "disposition": $(if [ -n "$disposition" ]; then printf '"%s"' "$(json_escape "$disposition")"; else printf 'null'; fi)
}
EOF
}

create_task() {
  task_id=""
  branch=""
  owner=${FIREBREAK_TASK_OWNER:-autonomous-operator}
  base_ref=${FIREBREAK_TASK_BASE_REF:-}
  resume_existing=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --task-id)
        task_id=$2
        shift 2
        ;;
      --branch)
        branch=$2
        shift 2
        ;;
      --owner)
        owner=$2
        shift 2
        ;;
      --base-ref)
        base_ref=$2
        shift 2
        ;;
      --resume)
        resume_existing=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ -z "$task_id" ] || [ -z "$branch" ]; then
    usage
  fi

  validate_task_id "$task_id"
  require_absolute_dir "$state_dir" "task state dir"
  require_absolute_dir "$worktree_root" "task worktree root"
  require_absolute_dir "$shared_root" "task shared root"

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$repo_root" ] || ! [ -f "$repo_root/flake.nix" ]; then
    echo "task creation must run from inside the Firebreak repository" >&2
    exit 1
  fi
  require_primary_checkout "$repo_root"
  if [ -z "$base_ref" ]; then
    base_ref=$(resolve_task_base_ref "$repo_root")
  fi

  task_root=$state_dir/$task_id
  metadata_path=$task_root/metadata.json
  if [ -e "$task_root" ]; then
    if [ "$resume_existing" = "1" ] && [ -f "$metadata_path" ]; then
      load_task "$task_id"
      if [ "$status" != "active" ]; then
        echo "cannot resume inactive task '$task_id' with status '$status'" >&2
        exit 125
      fi
      cat "$metadata_path"
      exit 0
    fi
    echo "task already exists: $task_id" >&2
    exit 125
  fi

  mkdir -p "$state_dir" "$worktree_root"
  worktree_path=$worktree_root/$task_id
  if [ -e "$worktree_path" ]; then
    echo "target worktree path already exists: $worktree_path" >&2
    exit 126
  fi

  worktree_shared_root=$shared_root/shared/$task_id

  FIREBREAK_TASK_STATE_DIR="$state_dir" \
    FIREBREAK_TASK_WORKTREE_ROOT="$worktree_root" \
    FIREBREAK_TASK_SHARED_ROOT="$worktree_shared_root" \
    FIREBREAK_WORKTREE_BASE_REF="$base_ref" \
    "$repo_root/scripts/new-worktree.sh" "$branch" "$task_id" >/dev/null
  sync_primary_checkout_to_worktree "$repo_root" "$worktree_path"

  validation_root=$task_root/validation
  runtime_id=$(printf '%s' "$task_id" | sha256sum | cut -c1-16)
  runtime_root=$shared_root/rt/$runtime_id
  vm_state_root=$runtime_root/vm
  artifact_root=$task_root/artifacts
  tmp_root=$runtime_root/tmp
  cloud_state_root=$runtime_root/cloud
  primary_checkout=$repo_root
  created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  status="active"
  disposition=""
  closed_at=""

  write_metadata
  printf '%s\n' "$base_ref" >"$task_root/base-ref"
  printf '%s\n' "$shared_root" >"$task_root/shared-root"

  cat "$metadata_path"
}

show_task() {
  task_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --task-id)
        task_id=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ -z "$task_id" ]; then
    usage
  fi

  load_task "$task_id"
  cat "$metadata_path"
}

validate_task() {
  task_id=""
  suite_name=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --task-id)
        task_id=$2
        shift 2
        ;;
      -*)
        usage
        ;;
      *)
        if [ -n "$suite_name" ]; then
          usage
        fi
        suite_name=$1
        shift
        ;;
    esac
  done

  if [ -z "$task_id" ] || [ -z "$suite_name" ]; then
    usage
  fi
  validate_suite_name "$suite_name"

  load_task "$task_id"
  if [ "$status" != "active" ]; then
    echo "cannot validate inactive task '$task_id' with status '$status'" >&2
    exit 1
  fi
  if ! [ -d "$worktree_path" ]; then
    echo "task worktree is missing: $worktree_path" >&2
    exit 1
  fi

  validation_state_dir=$validation_root/$suite_name
  suite_runtime_id=$(printf '%s' "$suite_name" | sha256sum | cut -c1-12)
  task_tmp_dir=$tmp_root/$suite_runtime_id
  task_vm_state_dir=$vm_state_root/$suite_runtime_id
  task_cloud_state_dir=$cloud_state_root/$suite_runtime_id
  mkdir -p "$validation_state_dir" "$task_tmp_dir" "$task_vm_state_dir" "$task_cloud_state_dir" "$artifact_root"

  run_flake_script=$worktree_path/scripts/run-flake.sh
  if ! [ -f "$run_flake_script" ]; then
    echo "task worktree is missing the flake helper: $run_flake_script" >&2
    exit 1
  fi

  set +e
  validation_output=$(
    cd "$worktree_path"
    FIREBREAK_TASK_ID="$task_id" \
      FIREBREAK_TASK_ROOT="$task_root" \
      FIREBREAK_INSTANCE_DIR="$task_vm_state_dir" \
      FIREBREAK_VALIDATION_STATE_DIR="$validation_state_dir" \
      FIREBREAK_STATE_DIR="$task_cloud_state_dir" \
      FIREBREAK_TMPDIR="$task_tmp_dir" \
      FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
      bash "$run_flake_script" run .#firebreak-internal-validate -- run "$suite_name" --state-dir "$validation_state_dir"
  )
  validation_status=$?
  set -e

  printf '%s\n' "$validation_output" >"$artifact_root/latest-validation-${suite_name}.json"
  printf '%s\n' "$validation_status" >"$artifact_root/latest-validation-${suite_name}.exit_code"
  printf '%s\n' "$validation_output"
  exit "$validation_status"
}

close_task() {
  task_id=""
  requested_disposition=""
  cleanup_worktree=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --task-id)
        task_id=$2
        shift 2
        ;;
      --disposition)
        requested_disposition=$2
        shift 2
        ;;
      --cleanup-worktree)
        cleanup_worktree=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ -z "$task_id" ] || [ -z "$requested_disposition" ]; then
    usage
  fi

  load_task "$task_id"
  status="closed"
  disposition=$requested_disposition
  closed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  write_metadata

  cat >"$task_root/review/final-disposition.json" <<EOF
{
  "task_id": "$(json_escape "$task_id")",
  "disposition": "$(json_escape "$disposition")",
  "closed_at": "$(json_escape "$closed_at")",
  "cleanup_worktree": $cleanup_worktree
}
EOF

  if [ "$cleanup_worktree" = "1" ] && [ -d "$worktree_path" ]; then
    git -C "$primary_checkout" worktree remove --force "$worktree_path"
  fi

  cat "$metadata_path"
}

case "$command" in
  create)
    shift
    create_task "$@"
    ;;
  show)
    shift
    show_task "$@"
    ;;
  validate)
    shift
    validate_task "$@"
    ;;
  close)
    shift
    close_task "$@"
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak internal task subcommand: $command" >&2
    usage
    ;;
esac
