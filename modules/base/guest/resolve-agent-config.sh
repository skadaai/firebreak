#!/usr/bin/env bash
set -eu

load_firebreak_shared_agent_defaults() {
  env_file=${FIREBREAK_SHARED_AGENT_CONFIG_ENV_FILE:-/run/microvm-host-meta/firebreak-shared-agent.env}
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

require_env() {
  key=$1
  value=${!key:-}
  if [ -z "$value" ]; then
    printf '%s\n' "missing required Firebreak config resolver env: $key" >&2
    exit 1
  fi
}

load_firebreak_shared_agent_defaults

require_env FIREBREAK_AGENT_CONFIG_SPECIFIC_VAR
require_env FIREBREAK_AGENT_CONFIG_SUBDIR

specific_var=$FIREBREAK_AGENT_CONFIG_SPECIFIC_VAR
config_subdir=$FIREBREAK_AGENT_CONFIG_SUBDIR
display_name=${FIREBREAK_AGENT_CONFIG_DISPLAY_NAME:-agent}
workspace_dir_name=${FIREBREAK_AGENT_CONFIG_WORKSPACE_DIR_NAME:-.firebreak/$config_subdir}

mode=${!specific_var:-${AGENT_CONFIG:-host}}

case "$mode" in
  host)
    mounted_flag=${FIREBREAK_SHARED_AGENT_CONFIG_HOST_MOUNTED_FLAG:-/run/firebreak-shared-agent-config-host-mounted}
    if ! [ -e "$mounted_flag" ]; then
      printf '%s\n' "Firebreak host config share is not mounted for $display_name; use workspace, vm, or fresh mode, or inspect prepare-agent-session logs for the host-share mount failure." >&2
      exit 1
    fi
    config_dir=${FIREBREAK_SHARED_AGENT_CONFIG_HOST_MOUNT:-/run/agent-config-host-root}/$config_subdir
    ;;
  workspace)
    config_dir="$(resolve_start_dir)/$workspace_dir_name"
    ;;
  vm)
    config_dir=${FIREBREAK_SHARED_AGENT_CONFIG_VM_ROOT:-/var/lib/dev/.firebreak}/$config_subdir
    ;;
  fresh)
    config_dir=${FIREBREAK_SHARED_AGENT_CONFIG_FRESH_ROOT:-/run/firebreak-agent-config-fresh}/$config_subdir
    ;;
  *)
    printf '%s\n' "unsupported $display_name config mode: $mode" >&2
    printf '%s\n' "supported values: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

mkdir -p "$config_dir"
printf '%s\n' "$config_dir"
