#!/usr/bin/env bash
set -eu

load_firebreak_multi_agent_defaults() {
  env_file=${FIREBREAK_MULTI_AGENT_CONFIG_ENV_FILE:-/run/microvm-host-meta/firebreak-multi-agent.env}
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

load_firebreak_multi_agent_defaults

mode=${@SPECIFIC_CONFIG_VAR@:-${AGENT_CONFIG:-vm}}
host_path_override=${@SPECIFIC_HOST_PATH_VAR@:-}

case "$mode" in
  host)
    if [ -n "$host_path_override" ]; then
      echo "@SPECIFIC_HOST_PATH_VAR@ is not supported in this multi-agent sandbox; use AGENT_CONFIG_HOST_PATH as the shared host root." >&2
      exit 1
    fi
    mounted_flag=${FIREBREAK_MULTI_AGENT_CONFIG_HOST_MOUNTED_FLAG:-/run/firebreak-multi-agent-host-mounted}
    if ! [ -e "$mounted_flag" ]; then
      echo "Firebreak host config share is not mounted for @WRAPPER_DISPLAY_NAME@; use workspace, vm, or fresh mode, or inspect prepare-agent-session logs for the host-share mount failure." >&2
      exit 1
    fi
    config_dir=${FIREBREAK_MULTI_AGENT_CONFIG_HOST_MOUNT:-/run/agent-config-host-root}/@CONFIG_SUBDIR@
    ;;
  workspace)
    config_dir="$(resolve_start_dir)/.firebreak/@CONFIG_SUBDIR@"
    ;;
  vm)
    config_dir=${FIREBREAK_MULTI_AGENT_CONFIG_VM_ROOT:-/var/lib/dev/.firebreak}/@CONFIG_SUBDIR@
    ;;
  fresh)
    fresh_root=${FIREBREAK_MULTI_AGENT_CONFIG_FRESH_ROOT:-/run/firebreak-agent-config-fresh}
    mkdir -p "$fresh_root"
    config_dir=$(mktemp -d "$fresh_root/@CONFIG_SUBDIR@.XXXXXX")
    ;;
  *)
    echo "unsupported @WRAPPER_DISPLAY_NAME@ config mode: $mode" >&2
    echo "supported values: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

mkdir -p "$config_dir"
@CONFIG_ENV_EXPORTS@
exec @REAL_BIN@ "$@"
