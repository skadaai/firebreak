#!/usr/bin/env bash
set -eu

@FIREBREAK_SHARED_STATE_ROOT_LIB@

require_env() {
  key=$1
  value=${!key:-}
  if [ -z "$value" ]; then
    printf '%s\n' "missing required Firebreak state resolver env: $key" >&2
    exit 1
  fi
}

load_firebreak_shared_state_defaults

require_env FIREBREAK_STATE_MODE_SPECIFIC_VAR
require_env FIREBREAK_STATE_SUBDIR

specific_var=$FIREBREAK_STATE_MODE_SPECIFIC_VAR
state_subdir=$FIREBREAK_STATE_SUBDIR
display_name=${FIREBREAK_STATE_DISPLAY_NAME:-tool}

mode=${!specific_var:-${FIREBREAK_STATE_MODE:-host}}

case "$mode" in
  host)
    mounted_flag=${FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG:-/run/firebreak-shared-state-root-mounted}
    if ! [ -e "$mounted_flag" ]; then
      printf '%s\n' "Firebreak host state root is not mounted for $display_name; use workspace, vm, or fresh mode, or inspect prepare-agent-session logs for the host-share mount failure." >&2
      exit 1
    fi
    state_dir=${FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT:-/run/firebreak-state-root}/$state_subdir
    ;;
  workspace)
    state_dir=$(resolve_workspace_state_dir "$state_subdir")
    ;;
  vm)
    state_dir=${FIREBREAK_SHARED_STATE_ROOT_VM_ROOT:-@DEV_HOME@/.firebreak}/$state_subdir
    ;;
  fresh)
    state_dir=${FIREBREAK_SHARED_STATE_ROOT_FRESH_ROOT:-/run/firebreak-state-fresh}/$state_subdir
    ;;
  *)
    printf '%s\n' "unsupported $display_name state mode: $mode" >&2
    printf '%s\n' "supported values: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

if [ -L "$state_dir" ]; then
  if ! [ -d "$state_dir" ]; then
    printf '%s\n' "Firebreak resolved $display_name state path is a broken symlink: $state_dir" >&2
    exit 1
  fi
elif ! mkdir -p "$state_dir"; then
  printf '%s\n' "failed to create Firebreak state directory: $state_dir" >&2
  exit 1
fi

printf '%s\n' "$state_dir"
