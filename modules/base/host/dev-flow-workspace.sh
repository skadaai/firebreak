#!/usr/bin/env bash
set -eu

state_dir=${DEV_FLOW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak_dev-flow/workspaces}
workspace_root=${DEV_FLOW_WORKSPACE_ROOT:-$state_dir/checkouts}
shared_root=${DEV_FLOW_SHARED_ROOT:-$(dirname "$workspace_root")}
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  dev-flow workspace create --workspace-id ID --branch BRANCH [--owner NAME] [--base-ref REF] [--resume]
  dev-flow workspace show --workspace-id ID
  dev-flow workspace validate --workspace-id ID SUITE
  dev-flow workspace close --workspace-id ID --disposition VALUE [--cleanup-workspace]
EOF
  exit 1
}

json_escape() {
  value=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  value=$(printf '%s' "$value" | tr '\n' ' ')
  printf '%s' "$value"
}

validate_workspace_id() {
  case "$1" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "workspace id must be a single path-safe token without whitespace: $1" >&2
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
    echo "workspace creation must run from the primary checkout: $repo_root" >&2
    echo "current git-common-dir: $git_common_dir" >&2
    exit 1
  fi
}

sync_primary_checkout_to_workspace() {
  repo_root=$1
  target_workspace=$2

  (
    cd "$repo_root"

    git ls-files --deleted -z |
      while IFS= read -r -d '' path; do
        rm -f "$target_workspace/$path"
      done

    git ls-files --cached --modified --others --exclude-standard -z |
      while IFS= read -r -d '' path; do
        case "$path" in
          .codex|.codex/*|.claude|.claude/*|.direnv|.direnv/*|.agent-sandbox.env|result|result/*|*.img|*.socket)
            continue
            ;;
        esac

        mkdir -p "$(dirname "$target_workspace/$path")"
        cp -a "$path" "$target_workspace/$path"
      done
  )
}

load_workspace() {
  workspace_id=$1
  validate_workspace_id "$workspace_id"
  workspace_state_root=$state_dir/$workspace_id
  metadata_path=$workspace_state_root/metadata.json

  if ! [ -f "$metadata_path" ]; then
    echo "unknown workspace id: $workspace_id" >&2
    exit 1
  fi

  branch=$(cat "$workspace_state_root/branch")
  owner=$(cat "$workspace_state_root/owner")
  primary_checkout=$(cat "$workspace_state_root/primary-checkout")
  workspace_path=$(cat "$workspace_state_root/workspace-path")
  workspace_shared_root=$(cat "$workspace_state_root/shared-root")
  validation_root=$(cat "$workspace_state_root/validation-root")
  runtime_root=$(cat "$workspace_state_root/runtime-root")
  vm_state_root=$(cat "$workspace_state_root/vm-state-root")
  artifact_root=$(cat "$workspace_state_root/artifact-root")
  tmp_root=$(cat "$workspace_state_root/tmp-root")
  cloud_state_root=$(cat "$workspace_state_root/cloud-state-root")
  created_at=$(cat "$workspace_state_root/created-at")
  status=$(cat "$workspace_state_root/status")
  disposition=""
  closed_at=""
  if [ -f "$workspace_state_root/disposition" ]; then
    disposition=$(cat "$workspace_state_root/disposition")
  fi
  if [ -f "$workspace_state_root/closed-at" ]; then
    closed_at=$(cat "$workspace_state_root/closed-at")
  fi
  reuse_or_create="reuse"
  shared_path_constraints='["resolved shared paths must stay inside the workspace shared root",".codex, .claude, and .direnv remain shared unless the workspace owns the resolved path"]'
}

emit_metadata() {
  cat <<EOF
{
  "workspace_id": "$(json_escape "$workspace_id")",
  "status": "$(json_escape "$status")",
  "owner": "$(json_escape "$owner")",
  "branch": "$(json_escape "$branch")",
  "primary_checkout": "$(json_escape "$primary_checkout")",
  "workspace_path": "$(json_escape "$workspace_path")",
  "shared_root": "$(json_escape "$workspace_shared_root")",
  "workspace_state_root": "$(json_escape "$workspace_state_root")",
  "validation_root": "$(json_escape "$validation_root")",
  "runtime_root": "$(json_escape "$runtime_root")",
  "vm_state_root": "$(json_escape "$vm_state_root")",
  "artifact_root": "$(json_escape "$artifact_root")",
  "tmp_root": "$(json_escape "$tmp_root")",
  "cloud_state_root": "$(json_escape "$cloud_state_root")",
  "reuse_or_create": "$(json_escape "$reuse_or_create")",
  "shared_path_constraints": $shared_path_constraints,
  "created_at": "$(json_escape "$created_at")",
  "closed_at": $(if [ -n "$closed_at" ]; then printf '"%s"' "$(json_escape "$closed_at")"; else printf 'null'; fi),
  "disposition": $(if [ -n "$disposition" ]; then printf '"%s"' "$(json_escape "$disposition")"; else printf 'null'; fi)
}
EOF
}

write_metadata() {
  mkdir -p "$workspace_state_root" "$validation_root" "$runtime_root" "$vm_state_root" "$artifact_root" "$tmp_root" "$cloud_state_root" "$workspace_state_root/review"
  printf '%s\n' "$workspace_id" >"$workspace_state_root/workspace-id"
  printf '%s\n' "$branch" >"$workspace_state_root/branch"
  printf '%s\n' "$owner" >"$workspace_state_root/owner"
  printf '%s\n' "$primary_checkout" >"$workspace_state_root/primary-checkout"
  printf '%s\n' "$workspace_path" >"$workspace_state_root/workspace-path"
  printf '%s\n' "$workspace_shared_root" >"$workspace_state_root/shared-root"
  printf '%s\n' "$validation_root" >"$workspace_state_root/validation-root"
  printf '%s\n' "$runtime_root" >"$workspace_state_root/runtime-root"
  printf '%s\n' "$vm_state_root" >"$workspace_state_root/vm-state-root"
  printf '%s\n' "$artifact_root" >"$workspace_state_root/artifact-root"
  printf '%s\n' "$tmp_root" >"$workspace_state_root/tmp-root"
  printf '%s\n' "$cloud_state_root" >"$workspace_state_root/cloud-state-root"
  printf '%s\n' "$created_at" >"$workspace_state_root/created-at"
  printf '%s\n' "$status" >"$workspace_state_root/status"
  if [ -n "$disposition" ]; then
    printf '%s\n' "$disposition" >"$workspace_state_root/disposition"
  else
    rm -f "$workspace_state_root/disposition"
  fi
  if [ -n "$closed_at" ]; then
    printf '%s\n' "$closed_at" >"$workspace_state_root/closed-at"
  else
    rm -f "$workspace_state_root/closed-at"
  fi

  emit_metadata >"$metadata_path"
}

create_workspace() {
  workspace_id=""
  branch=""
  owner=${DEV_FLOW_WORKSPACE_OWNER:-autonomous-operator}
  base_ref=${DEV_FLOW_BASE_REF:-main}
  resume_existing=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workspace-id)
        workspace_id=$2
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

  if [ -z "$workspace_id" ] || [ -z "$branch" ]; then
    usage
  fi

  validate_workspace_id "$workspace_id"
  require_absolute_dir "$state_dir" "workspace state dir"
  require_absolute_dir "$workspace_root" "workspace root"
  require_absolute_dir "$shared_root" "workspace shared root"

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$repo_root" ] || ! [ -f "$repo_root/flake.nix" ]; then
    echo "workspace creation must run from inside the Firebreak repository" >&2
    exit 1
  fi
  require_primary_checkout "$repo_root"

  workspace_state_root=$state_dir/$workspace_id
  metadata_path=$workspace_state_root/metadata.json
  if [ -e "$workspace_state_root" ]; then
    if [ "$resume_existing" = "1" ] && [ -f "$metadata_path" ]; then
      load_workspace "$workspace_id"
      if [ "$status" != "active" ]; then
        echo "cannot resume inactive workspace '$workspace_id' with status '$status'" >&2
        exit 125
      fi
      reuse_or_create="reuse"
      emit_metadata
      exit 0
    fi
    echo "workspace already exists: $workspace_id" >&2
    exit 125
  fi

  mkdir -p "$state_dir" "$workspace_root"
  workspace_path=$workspace_root/$workspace_id
  if [ -e "$workspace_path" ]; then
    echo "target workspace path already exists: $workspace_path" >&2
    exit 126
  fi

  workspace_shared_root=$shared_root/shared/$workspace_id

  DEV_FLOW_STATE_DIR="$state_dir" \
    DEV_FLOW_WORKSPACE_ROOT="$workspace_root" \
    DEV_FLOW_SHARED_ROOT="$workspace_shared_root" \
    DEV_FLOW_BASE_REF="$base_ref" \
    "$repo_root/scripts/new-worktree.sh" "$branch" "$workspace_id" >/dev/null
  sync_primary_checkout_to_workspace "$repo_root" "$workspace_path"

  validation_root=$workspace_state_root/validation
  runtime_id=$(printf '%s' "$workspace_id" | sha256sum | cut -c1-16)
  runtime_root=$shared_root/rt/$runtime_id
  vm_state_root=$runtime_root/vm
  artifact_root=$workspace_state_root/artifacts
  tmp_root=$runtime_root/tmp
  cloud_state_root=$runtime_root/cloud
  primary_checkout=$repo_root
  created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  status="active"
  reuse_or_create="create"
  shared_path_constraints='["resolved shared paths must stay inside the workspace shared root",".codex, .claude, and .direnv remain shared unless the workspace owns the resolved path"]'
  disposition=""
  closed_at=""

  write_metadata
  printf '%s\n' "$base_ref" >"$workspace_state_root/base-ref"

  cat "$metadata_path"
}

show_workspace() {
  workspace_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workspace-id)
        workspace_id=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ -z "$workspace_id" ]; then
    usage
  fi

  load_workspace "$workspace_id"
  reuse_or_create="reuse"
  emit_metadata
}

validate_workspace() {
  workspace_id=""
  suite_name=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workspace-id)
        workspace_id=$2
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

  if [ -z "$workspace_id" ] || [ -z "$suite_name" ]; then
    usage
  fi
  validate_suite_name "$suite_name"

  load_workspace "$workspace_id"
  if [ "$status" != "active" ]; then
    echo "cannot validate inactive workspace '$workspace_id' with status '$status'" >&2
    exit 1
  fi
  if ! [ -d "$workspace_path" ]; then
    echo "workspace checkout is missing: $workspace_path" >&2
    exit 1
  fi

  validation_state_dir=$validation_root/$suite_name
  suite_runtime_id=$(printf '%s' "$suite_name" | sha256sum | cut -c1-12)
  workspace_tmp_dir=$tmp_root/$suite_runtime_id
  workspace_vm_state_dir=$vm_state_root/$suite_runtime_id
  workspace_cloud_state_dir=$cloud_state_root/$suite_runtime_id
  mkdir -p "$validation_state_dir" "$workspace_tmp_dir" "$workspace_vm_state_dir" "$workspace_cloud_state_dir" "$artifact_root"

  run_flake_script=$workspace_path/scripts/run-flake.sh
  if ! [ -f "$run_flake_script" ]; then
    echo "workspace checkout is missing the flake helper: $run_flake_script" >&2
    exit 1
  fi

  set +e
  validation_output=$(
    cd "$workspace_path"
    DEV_FLOW_WORKSPACE_ID="$workspace_id" \
      DEV_FLOW_WORKSPACE_STATE_ROOT="$workspace_state_root" \
      FIREBREAK_INSTANCE_DIR="$workspace_vm_state_dir" \
      DEV_FLOW_VALIDATION_STATE_DIR="$validation_state_dir" \
      FIREBREAK_STATE_DIR="$workspace_cloud_state_dir" \
      FIREBREAK_TMPDIR="$workspace_tmp_dir" \
      FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
      bash "$run_flake_script" run .#dev-flow-validate -- run "$suite_name" --state-dir "$validation_state_dir"
  )
  validation_status=$?
  set -e

  printf '%s\n' "$validation_output" >"$artifact_root/latest-validation-${suite_name}.json"
  printf '%s\n' "$validation_status" >"$artifact_root/latest-validation-${suite_name}.exit_code"
  printf '%s\n' "$validation_output"
  exit "$validation_status"
}

close_workspace() {
  workspace_id=""
  requested_disposition=""
  cleanup_workspace=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --workspace-id)
        workspace_id=$2
        shift 2
        ;;
      --disposition)
        requested_disposition=$2
        shift 2
        ;;
      --cleanup-workspace)
        cleanup_workspace=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ -z "$workspace_id" ] || [ -z "$requested_disposition" ]; then
    usage
  fi

  load_workspace "$workspace_id"
  status="closed"
  disposition=$requested_disposition
  closed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  write_metadata

  cat >"$workspace_state_root/review/final-disposition.json" <<EOF
{
  "workspace_id": "$(json_escape "$workspace_id")",
  "disposition": "$(json_escape "$disposition")",
  "closed_at": "$(json_escape "$closed_at")",
  "cleanup_workspace": $cleanup_workspace
}
EOF

  if [ "$cleanup_workspace" = "1" ] && [ -d "$workspace_path" ]; then
    git -C "$primary_checkout" worktree remove --force "$workspace_path"
  fi

  cat "$metadata_path"
}

case "$command" in
  create)
    shift
    create_workspace "$@"
    ;;
  show)
    shift
    show_workspace "$@"
    ;;
  validate)
    shift
    validate_workspace "$@"
    ;;
  close)
    shift
    close_workspace "$@"
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown dev-flow workspace subcommand: $command" >&2
    usage
    ;;
esac
