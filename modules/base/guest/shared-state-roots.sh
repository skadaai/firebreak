load_firebreak_shared_state_defaults() {
  env_file=${FIREBREAK_SHARED_STATE_ROOT_ENV_FILE:-/run/microvm-host-meta/firebreak-shared-state.env}
  if [ -r "$env_file" ]; then
    # shellcheck disable=SC1090
    . "$env_file"
  fi
}

resolve_start_dir() {
  if [ -r /run/microvm-start-dir ]; then
    cat /run/microvm-start-dir
  else
    printf '%s\n' /workspace
  fi
}

resolve_state_project_root() {
  base_dir=$1
  project_root=$(git -C "$base_dir" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$project_root" ]; then
    printf '%s\n' "$project_root"
  else
    printf '%s\n' "$base_dir"
  fi
}

firebreak_state_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    return
  fi

  printf '%s\n' "Firebreak requires sha256sum or shasum to derive workspace state roots" >&2
  exit 1
}

resolve_workspace_state_dir() {
  config_subdir=$1
  start_dir=$(resolve_start_dir)
  project_root=$(resolve_state_project_root "$start_dir")
  project_key=$(firebreak_state_sha256 "$project_root")
  project_key=$(printf '%.16s' "$project_key")

  workspace_state_root=${FIREBREAK_SHARED_STATE_ROOT_VM_ROOT:-/var/lib/dev/.firebreak}
  mounted_flag=${FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG:-/run/firebreak-shared-state-root-mounted}
  if [ -e "$mounted_flag" ]; then
    workspace_state_root=${FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT:-/run/firebreak-state-root}
  fi

  printf '%s\n' "$workspace_state_root/workspaces/$project_key/$config_subdir"
}
