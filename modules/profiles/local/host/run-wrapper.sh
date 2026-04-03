set -eu

@FIREBREAK_PROJECT_CONFIG_LIB@

host_cwd=$PWD
host_uid=$(id -u)
host_gid=$(id -g)
firebreak_load_project_config
resolved_firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
firebreak_state_root=${FIREBREAK_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}/firebreak}
agent_specific_config_var=@AGENT_ENV_PREFIX@_CONFIG
agent_specific_config=${!agent_specific_config_var:-}
agent_config_mode=${agent_specific_config:-${AGENT_CONFIG:-host}}
requested_vm_mode=${FIREBREAK_VM_MODE:-run}
agent_session_mode=agent
default_agent_command=@DEFAULT_AGENT_COMMAND@
agent_command_override=""
shell_command_override=${AGENT_VM_COMMAND:-}
shared_agent_config_host_dir=""
workspace_bootstrap_config_host_dir=@WORKSPACE_BOOTSTRAP_CONFIG_HOST_DIR@
host_config_adoption_enabled=@HOST_CONFIG_ADOPTION_ENABLED@
default_control_socket=@CONTROL_SOCKET@
instance_state_dir=${FIREBREAK_INSTANCE_DIR:-}
instance_ephemeral=${FIREBREAK_INSTANCE_EPHEMERAL:-0}
debug_keep_runtime=${FIREBREAK_DEBUG_KEEP_RUNTIME:-0}
runner_workdir=$host_cwd
control_socket=$default_control_socket

reject_whitespace_path() {
  path=$1
  description=$2
  case "$path" in
    *[[:space:]]*)
      echo "$description contains whitespace, which microvm runtime share injection does not support: $path" >&2
      exit 1
      ;;
  esac
}

resolve_host_dir() {
  path=$1
  if [ "$path" = "~" ]; then
    printf '%s\n' "$HOME"
  elif [ "${path#\~/}" != "$path" ]; then
    printf '%s\n' "$HOME/${path#\~/}"
  else
    printf '%s\n' "$path"
  fi
}

ensure_host_agent_config_subdir() {
  host_root=$1
  config_subdir=$2
  bootstrap_target=$3
  host_config_path=$host_root/$config_subdir

  mkdir -p "$host_root"

  if [ -n "$bootstrap_target" ] && ! [ -e "$host_config_path" ] && ! [ -L "$host_config_path" ] && { [ -e "$bootstrap_target" ] || [ -L "$bootstrap_target" ]; }; then
    reject_whitespace_path "$bootstrap_target" "host config bootstrap target"
    ln -s "$bootstrap_target" "$host_config_path"
    printf '%s\n' "firebreak: adopted existing agent config as $host_config_path -> $bootstrap_target" >&2
    return 0
  fi

  if ! [ -e "$host_config_path" ] && ! [ -L "$host_config_path" ]; then
    mkdir -p "$host_config_path"
  fi
}

append_optional_env_default() {
  key=$1
  value=$2
  [ -n "$value" ] || return 0

  printf -v quoted_value '%q' "$value"
  printf ": \"\${%s:=%s}\"\n" "$key" "$quoted_value" >> "$shared_agent_config_env_file"
  printf 'export %s\n' "$key" >> "$shared_agent_config_env_file"
}

default_agent_config_host_dir=$(resolve_host_dir "${AGENT_CONFIG_HOST_PATH:-@DEFAULT_AGENT_CONFIG_HOST_DIR@}")
workspace_bootstrap_target=""
if [ -n "$workspace_bootstrap_config_host_dir" ]; then
  workspace_bootstrap_target=$(resolve_host_dir "$workspace_bootstrap_config_host_dir")
fi
shared_agent_config_host_dir=$default_agent_config_host_dir

reject_whitespace_path "$host_cwd" "current working directory"
reject_whitespace_path "$resolved_firebreak_tmp_root" "Firebreak temporary runtime directory"
firebreak_tmp_root=$resolved_firebreak_tmp_root
mkdir -p "$firebreak_tmp_root"
host_runtime_dir=$(mktemp -d "$firebreak_tmp_root/r.XXXXXX")
host_meta_dir=$host_runtime_dir/m
host_exec_output_dir=$host_runtime_dir/o
host_instance_dir=$host_runtime_dir/instance
runner_stdout_log=$host_runtime_dir/runner.out
runner_stderr_log=$host_runtime_dir/runner.err
virtiofsd_hostcwd_log=$host_runtime_dir/v-cwd.log
virtiofsd_shared_agent_config_log=$host_runtime_dir/v-shared-cfg.log
virtiofsd_agent_exec_log=$host_runtime_dir/v-out.log
hostcwd_socket=$host_runtime_dir/cwd.sock
shared_agent_config_socket=$host_runtime_dir/shared-cfg.sock
agent_exec_output_socket=$host_runtime_dir/out.sock

case "$shared_agent_config_host_dir" in
  /*) ;;
  *)
    echo "AGENT_CONFIG_HOST_PATH must resolve to an absolute host path for Firebreak host config root: $shared_agent_config_host_dir" >&2
    exit 1
    ;;
esac
reject_whitespace_path "$shared_agent_config_host_dir" "Firebreak host config root"
mkdir -p "$shared_agent_config_host_dir"

if [ -n "$instance_state_dir" ]; then
  case "$instance_state_dir" in
    /*) ;;
    *)
      echo "FIREBREAK_INSTANCE_DIR must be an absolute host path: $instance_state_dir" >&2
      exit 1
      ;;
  esac
  reject_whitespace_path "$instance_state_dir" "instance state directory"
  mkdir -p "$instance_state_dir"
  runner_workdir=$instance_state_dir
  control_socket=$instance_state_dir/$default_control_socket
elif [ "$instance_ephemeral" = "1" ]; then
  mkdir -p "$host_instance_dir"
  runner_workdir=$host_instance_dir
  control_socket=$host_instance_dir/$default_control_socket
else
  reject_whitespace_path "$firebreak_state_root" "Firebreak state root"
  sha256_output=$(printf '%s' "$host_cwd" | sha256sum) || {
    echo "failed to hash current working directory for Firebreak instance state" >&2
    exit 1
  }
  default_instance_key=${sha256_output%% *}
  if [ -z "$default_instance_key" ]; then
    echo "failed to derive Firebreak instance key from current working directory hash" >&2
    exit 1
  fi
  default_instance_key=$(printf '%.16s' "$default_instance_key")
  default_instance_dir=$firebreak_state_root/instances/${default_control_socket%.socket}-$default_instance_key
  reject_whitespace_path "$default_instance_dir" "default instance state directory"
  mkdir -p "$default_instance_dir"
  runner_workdir=$default_instance_dir
  control_socket=$default_instance_dir/$default_control_socket
fi

case "$requested_vm_mode" in
  run)
    agent_session_mode=agent
    ;;
  shell)
    agent_session_mode=shell
    ;;
  *)
    echo "unsupported FIREBREAK_VM_MODE: $requested_vm_mode" >&2
    echo "supported values: run, shell" >&2
    exit 1
    ;;
esac

if [ "$agent_session_mode" = "agent" ] && [ "$#" -gt 0 ]; then
  if [ -z "$default_agent_command" ]; then
    echo "this VM mode does not support forwarding CLI arguments to an agent command" >&2
    exit 1
  fi

  agent_session_mode=agent-exec
  agent_command_override=$default_agent_command
  for arg in "$@"; do
    printf -v quoted_arg '%q' "$arg"
    agent_command_override="$agent_command_override $quoted_arg"
  done
  set --
fi

if [ -n "$shell_command_override" ]; then
  agent_session_mode=agent-exec
  agent_command_override=$shell_command_override
fi

case "$agent_config_mode" in
  host|workspace|vm|fresh)
    ;;
  *)
    echo "unsupported agent config mode: $agent_config_mode" >&2
    echo "supported modes: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

if [ "$host_config_adoption_enabled" = "1" ] && [ "$agent_config_mode" = "host" ]; then
  ensure_host_agent_config_subdir "$shared_agent_config_host_dir" "@AGENT_CONFIG_SUBDIR@" "$workspace_bootstrap_target"
fi

# shellcheck disable=SC2329
cleanup() {
  if [ -n "${hostcwd_virtiofsd_pid:-}" ]; then
    kill "$hostcwd_virtiofsd_pid" 2>/dev/null || true
    wait "$hostcwd_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${shared_agent_config_virtiofsd_pid:-}" ]; then
    kill "$shared_agent_config_virtiofsd_pid" 2>/dev/null || true
    wait "$shared_agent_config_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${agent_exec_output_virtiofsd_pid:-}" ]; then
    kill "$agent_exec_output_virtiofsd_pid" 2>/dev/null || true
    wait "$agent_exec_output_virtiofsd_pid" 2>/dev/null || true
  fi
  rm -f "$control_socket"
  if [ "$debug_keep_runtime" = "1" ]; then
    echo "keeping Firebreak runtime directory: $host_runtime_dir" >&2
  else
    rm -rf "$host_runtime_dir"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$host_meta_dir"
mkdir -p "$host_exec_output_dir"
rm -f "$control_socket"
shared_agent_config_env_file=$host_meta_dir/firebreak-shared-agent.env

start_virtiofsd() {
  shared_dir=$1
  socket_path=$2
  log_path=$3
  virtiofsd \
    --socket-path="$socket_path" \
    --shared-dir="$shared_dir" \
    --sandbox=none \
    --posix-acl \
    --xattr >"$log_path" 2>&1 &
  started_virtiofsd_pid=$!

  for _ in $(seq 1 50); do
    if [ -S "$socket_path" ]; then
      return 0
    fi
    sleep 0.1
  done

  kill "$started_virtiofsd_pid" 2>/dev/null || true
  wait "$started_virtiofsd_pid" 2>/dev/null || true
  echo "virtiofsd did not create socket: $socket_path" >&2
  exit 1
}

printf '%s\n' "$host_cwd" > "$host_meta_dir/mount-path"
printf '%s\n' "$host_uid" > "$host_meta_dir/host-uid"
printf '%s\n' "$host_gid" > "$host_meta_dir/host-gid"
printf '%s\n' "$agent_config_mode" > "$host_meta_dir/agent-config-mode"
printf '%s\n' "$agent_session_mode" > "$host_meta_dir/agent-session-mode"
: > "$shared_agent_config_env_file"
append_optional_env_default "AGENT_CONFIG" "${AGENT_CONFIG:-}"
append_optional_env_default "AGENT_CONFIG_HOST_PATH" "${AGENT_CONFIG_HOST_PATH:-}"
append_optional_env_default "CODEX_CONFIG" "${CODEX_CONFIG:-}"
append_optional_env_default "CLAUDE_CONFIG" "${CLAUDE_CONFIG:-}"
if [ -n "$agent_command_override" ]; then
  printf '%s\n' "$agent_command_override" > "$host_meta_dir/agent-command"
fi

start_virtiofsd "$host_cwd" "$hostcwd_socket" "$virtiofsd_hostcwd_log"
hostcwd_virtiofsd_pid=$started_virtiofsd_pid

if [ -n "$shared_agent_config_host_dir" ]; then
  start_virtiofsd "$shared_agent_config_host_dir" "$shared_agent_config_socket" "$virtiofsd_shared_agent_config_log"
  shared_agent_config_virtiofsd_pid=$started_virtiofsd_pid
fi
if [ "$agent_session_mode" = "agent-exec" ]; then
  start_virtiofsd "$host_exec_output_dir" "$agent_exec_output_socket" "$virtiofsd_agent_exec_log"
  agent_exec_output_virtiofsd_pid=$started_virtiofsd_pid
fi

runner_status=0
if [ "$agent_session_mode" = "agent-exec" ]; then
  (
    cd "$runner_workdir"
    env \
      MICROVM_HOST_META_DIR="$host_meta_dir" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_SHARED_AGENT_CONFIG_DIR="$shared_agent_config_host_dir" \
      MICROVM_SHARED_AGENT_CONFIG_SOCKET="$shared_agent_config_socket" \
      MICROVM_AGENT_EXEC_OUTPUT_SOCKET="$agent_exec_output_socket" \
      @RUNNER@ "$@"
  ) >"$runner_stdout_log" 2>"$runner_stderr_log" || runner_status=$?
else
  (
    cd "$runner_workdir"
    env \
      MICROVM_HOST_META_DIR="$host_meta_dir" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_SHARED_AGENT_CONFIG_DIR="$shared_agent_config_host_dir" \
      MICROVM_SHARED_AGENT_CONFIG_SOCKET="$shared_agent_config_socket" \
      @RUNNER@ "$@"
  ) || runner_status=$?
fi

if [ "$agent_session_mode" = "agent-exec" ]; then
  if [ -f "$host_exec_output_dir/stdout" ]; then
    cat "$host_exec_output_dir/stdout"
  fi
  if [ -f "$host_exec_output_dir/stderr" ]; then
    cat "$host_exec_output_dir/stderr" >&2
  fi

  if [ -f "$host_exec_output_dir/exit_code" ]; then
    IFS= read -r command_status < "$host_exec_output_dir/exit_code" || command_status=$runner_status
    if [ "$command_status" -ne 0 ] && [ -s "$runner_stderr_log" ]; then
      cat "$runner_stderr_log" >&2
    fi
    if [ "$command_status" -ne 0 ]; then
      if [ -s "$virtiofsd_hostcwd_log" ]; then
        cat "$virtiofsd_hostcwd_log" >&2
      fi
      if [ -s "$virtiofsd_shared_agent_config_log" ]; then
        cat "$virtiofsd_shared_agent_config_log" >&2
      fi
      if [ -s "$virtiofsd_agent_exec_log" ]; then
        cat "$virtiofsd_agent_exec_log" >&2
      fi
    fi
    exit "$command_status"
  fi

  if [ -s "$runner_stderr_log" ]; then
    cat "$runner_stderr_log" >&2
  fi
  if [ -s "$virtiofsd_hostcwd_log" ]; then
    cat "$virtiofsd_hostcwd_log" >&2
  fi
  if [ -s "$virtiofsd_shared_agent_config_log" ]; then
    cat "$virtiofsd_shared_agent_config_log" >&2
  fi
  if [ -s "$virtiofsd_agent_exec_log" ]; then
    cat "$virtiofsd_agent_exec_log" >&2
  fi
fi

exit "$runner_status"
