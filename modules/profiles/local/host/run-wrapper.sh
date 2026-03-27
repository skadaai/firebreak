set -eu

@FIREBREAK_PROJECT_CONFIG_LIB@

host_cwd=$PWD
host_uid=$(id -u)
host_gid=$(id -g)
firebreak_load_project_config
resolved_firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
firebreak_state_root=${FIREBREAK_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}/firebreak}
agent_specific_config_var=@AGENT_ENV_PREFIX@_CONFIG
agent_specific_host_path_var=@AGENT_ENV_PREFIX@_CONFIG_HOST_PATH
agent_specific_config=${!agent_specific_config_var:-}
agent_specific_host_path=${!agent_specific_host_path_var:-}
agent_config_mode=${agent_specific_config:-${AGENT_CONFIG:-vm}}
requested_vm_mode=${FIREBREAK_VM_MODE:-run}
agent_session_mode_override=${FIREBREAK_AGENT_SESSION_MODE_OVERRIDE:-}
agent_session_mode=agent
default_agent_command=@DEFAULT_AGENT_COMMAND@
agent_command_override=""
shell_command_override=${AGENT_VM_COMMAND:-}
agent_config_host_dir=""
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

resolve_symlink_target() {
  path=$1
  realpath -m "$path"
}

default_agent_config_host_dir=$(resolve_host_dir "${agent_specific_host_path:-${AGENT_CONFIG_HOST_PATH:-@DEFAULT_AGENT_CONFIG_HOST_DIR@}}")

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
virtiofsd_agent_config_log=$host_runtime_dir/v-cfg.log
virtiofsd_agent_exec_log=$host_runtime_dir/v-out.log
virtiofsd_worker_bridge_log=$host_runtime_dir/v-worker.log
hostcwd_socket=$host_runtime_dir/cwd.sock
agent_config_socket=$host_runtime_dir/cfg.sock
agent_exec_output_socket=$host_runtime_dir/out.sock
worker_bridge_dir=$host_runtime_dir/w
worker_bridge_socket=$host_runtime_dir/worker.sock
worker_bridge_socket_env=""
worker_bridge_server_log=$host_runtime_dir/worker-bridge.log
worker_bridge_server_script=$host_runtime_dir/firebreak-worker-bridge-host.sh
worker_helper_script=$host_runtime_dir/firebreak-worker.sh
worker_bridge_enabled=@WORKER_BRIDGE_ENABLED@
wrapper_trace_log=$host_runtime_dir/wrapper-trace.log

trace_wrapper() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >>"$wrapper_trace_log"
}

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

runtime_debug_file=$runner_workdir/.firebreak-runtime.json

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

if [ -n "$agent_session_mode_override" ]; then
  case "$agent_session_mode_override" in
    shell|agent|agent-exec|agent-attach-exec)
      agent_session_mode=$agent_session_mode_override
      ;;
    *)
      echo "unsupported FIREBREAK_AGENT_SESSION_MODE_OVERRIDE: $agent_session_mode_override" >&2
      exit 1
      ;;
  esac
fi

if [ -z "$agent_command_override" ]; then
  case "$agent_session_mode" in
    agent-exec|agent-attach-exec)
      if [ -n "$default_agent_command" ]; then
        agent_command_override=$default_agent_command
      fi
      ;;
  esac
fi

case "$agent_config_mode" in
  host)
    agent_config_host_dir=$default_agent_config_host_dir

    case "$agent_config_host_dir" in
      /*) ;;
      *)
        echo "AGENT_CONFIG_HOST_PATH must resolve to an absolute host path: $agent_config_host_dir" >&2
        exit 1
        ;;
    esac

    reject_whitespace_path "$agent_config_host_dir" "agent host config path"

    mkdir -p "$agent_config_host_dir"
    ;;
  workspace|vm|fresh)
    ;;
  *)
    echo "unsupported agent config mode: $agent_config_mode" >&2
    echo "supported modes: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

workspace_agent_config_path=$host_cwd/@AGENT_CONFIG_DIR_NAME@
if [ "$agent_config_mode" = "workspace" ] && [ -L "$workspace_agent_config_path" ]; then
  resolved_symlink_target=$(resolve_symlink_target "$workspace_agent_config_path")
    reject_whitespace_path "$resolved_symlink_target" "workspace agent config symlink target"
    case "$resolved_symlink_target" in
      "$host_cwd"|"$host_cwd"/*)
        ;;
      *)
        agent_config_mode=host
        agent_config_host_dir=$resolved_symlink_target
        target_parent=$(dirname "$agent_config_host_dir")
        if ! [ -d "$agent_config_host_dir" ] && ! [ -w "$target_parent" ]; then
          echo "workspace agent config symlink target is not writable on the host; falling back to $default_agent_config_host_dir" >&2
          agent_config_host_dir=$default_agent_config_host_dir
        fi
        mkdir -p "$agent_config_host_dir"
        ;;
  esac
fi

# shellcheck disable=SC2329
cleanup() {
  if [ -n "${hostcwd_virtiofsd_pid:-}" ]; then
    kill "$hostcwd_virtiofsd_pid" 2>/dev/null || true
    wait "$hostcwd_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${agent_config_virtiofsd_pid:-}" ]; then
    kill "$agent_config_virtiofsd_pid" 2>/dev/null || true
    wait "$agent_config_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${agent_exec_output_virtiofsd_pid:-}" ]; then
    kill "$agent_exec_output_virtiofsd_pid" 2>/dev/null || true
    wait "$agent_exec_output_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${worker_bridge_virtiofsd_pid:-}" ]; then
    kill "$worker_bridge_virtiofsd_pid" 2>/dev/null || true
    wait "$worker_bridge_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${worker_bridge_server_pid:-}" ]; then
    kill "$worker_bridge_server_pid" 2>/dev/null || true
    wait "$worker_bridge_server_pid" 2>/dev/null || true
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
mkdir -p "$worker_bridge_dir/requests"
rm -f "$control_socket"
: >"$wrapper_trace_log"

cat >"$runtime_debug_file" <<EOF
{
  "host_runtime_dir": "$(printf '%s' "$host_runtime_dir" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "runner_workdir": "$(printf '%s' "$runner_workdir" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "session_mode": "$(printf '%s' "$agent_session_mode" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "control_socket": "$(printf '%s' "$control_socket" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "agent_exec_output_dir": "$(printf '%s' "$host_exec_output_dir" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "wrapper_trace_log": "$(printf '%s' "$wrapper_trace_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "runner_stdout_log": "$(printf '%s' "$runner_stdout_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "runner_stderr_log": "$(printf '%s' "$runner_stderr_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_hostcwd_log": "$(printf '%s' "$virtiofsd_hostcwd_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_agent_config_log": "$(printf '%s' "$virtiofsd_agent_config_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_agent_exec_log": "$(printf '%s' "$virtiofsd_agent_exec_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_worker_bridge_log": "$(printf '%s' "$virtiofsd_worker_bridge_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "worker_bridge_server_log": "$(printf '%s' "$worker_bridge_server_log" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}
EOF
trace_wrapper "wrapper-start"

if [ "$worker_bridge_enabled" = "1" ]; then
  cat >"$worker_helper_script" <<'__FIREBREAK_WORKER_SCRIPT__'
@FIREBREAK_WORKER_LIB@
__FIREBREAK_WORKER_SCRIPT__
  cat >"$worker_bridge_server_script" <<'__FIREBREAK_WORKER_BRIDGE_HOST_SCRIPT__'
@FIREBREAK_WORKER_BRIDGE_HOST_LIB@
__FIREBREAK_WORKER_BRIDGE_HOST_SCRIPT__
  chmod 0555 "$worker_helper_script" "$worker_bridge_server_script"
fi

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
if [ -n "$agent_command_override" ]; then
  printf '%s\n' "$agent_command_override" > "$host_meta_dir/agent-command"
fi

start_virtiofsd "$host_cwd" "$hostcwd_socket" "$virtiofsd_hostcwd_log"
hostcwd_virtiofsd_pid=$started_virtiofsd_pid
trace_wrapper "virtiofs-hostcwd-ready"

if [ -n "$agent_config_host_dir" ]; then
  start_virtiofsd "$agent_config_host_dir" "$agent_config_socket" "$virtiofsd_agent_config_log"
  agent_config_virtiofsd_pid=$started_virtiofsd_pid
  trace_wrapper "virtiofs-agent-config-ready"
fi
if [ "$agent_session_mode" = "agent-exec" ] || [ "$agent_session_mode" = "agent-attach-exec" ]; then
  start_virtiofsd "$host_exec_output_dir" "$agent_exec_output_socket" "$virtiofsd_agent_exec_log"
  agent_exec_output_virtiofsd_pid=$started_virtiofsd_pid
  trace_wrapper "virtiofs-agent-exec-ready"
fi
if [ "$worker_bridge_enabled" = "1" ]; then
  start_virtiofsd "$worker_bridge_dir" "$worker_bridge_socket" "$virtiofsd_worker_bridge_log"
  worker_bridge_virtiofsd_pid=$started_virtiofsd_pid
  worker_bridge_socket_env=$worker_bridge_socket
  env \
    FIREBREAK_FLAKE_REF='@FIREBREAK_FLAKE_REF@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG='1' \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    FIREBREAK_WORKER_BRIDGE_DIR="$worker_bridge_dir" \
    bash "$worker_bridge_server_script" "$worker_bridge_dir" "$worker_helper_script" >"$worker_bridge_server_log" 2>&1 &
  worker_bridge_server_pid=$!
  trace_wrapper "worker-bridge-ready"
fi

runner_status=0
trace_wrapper "runner-start"
if [ "$agent_session_mode" = "agent-exec" ]; then
  (
    cd "$runner_workdir"
    env \
      MICROVM_HOST_META_DIR="$host_meta_dir" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_AGENT_CONFIG_HOST_DIR="$agent_config_host_dir" \
      MICROVM_AGENT_CONFIG_HOST_SOCKET="$agent_config_socket" \
      MICROVM_AGENT_EXEC_OUTPUT_SOCKET="$agent_exec_output_socket" \
      MICROVM_WORKER_BRIDGE_SOCKET="$worker_bridge_socket_env" \
      @RUNNER@ "$@"
  ) >"$runner_stdout_log" 2>"$runner_stderr_log" || runner_status=$?
elif [ "$agent_session_mode" = "agent-attach-exec" ]; then
  attach_runner_script=$host_runtime_dir/attached-runner.sh
  quoted_runner_args=""
  for arg in "$@"; do
    printf -v quoted_runner_arg '%q' "$arg"
    quoted_runner_args="$quoted_runner_args $quoted_runner_arg"
  done
  cat >"$attach_runner_script" <<EOF
set -eu
cd "$(printf '%s' "$runner_workdir" | sed "s/'/'\\\\''/g")"
export MICROVM_HOST_META_DIR='$(printf '%s' "$host_meta_dir" | sed "s/'/'\\\\''/g")'
export MICROVM_HOST_CWD_SOCKET='$(printf '%s' "$hostcwd_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_AGENT_CONFIG_HOST_DIR='$(printf '%s' "$agent_config_host_dir" | sed "s/'/'\\\\''/g")'
export MICROVM_AGENT_CONFIG_HOST_SOCKET='$(printf '%s' "$agent_config_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_AGENT_EXEC_OUTPUT_SOCKET='$(printf '%s' "$agent_exec_output_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_WORKER_BRIDGE_SOCKET='$(printf '%s' "$worker_bridge_socket_env" | sed "s/'/'\\\\''/g")'
exec @RUNNER@$quoted_runner_args
EOF
  chmod 0555 "$attach_runner_script"
  script -qefc "$(printf "%s" "$attach_runner_script")" "$runner_stdout_log" || runner_status=$?
else
  (
    cd "$runner_workdir"
    env \
      MICROVM_HOST_META_DIR="$host_meta_dir" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_AGENT_CONFIG_HOST_DIR="$agent_config_host_dir" \
      MICROVM_AGENT_CONFIG_HOST_SOCKET="$agent_config_socket" \
      MICROVM_WORKER_BRIDGE_SOCKET="$worker_bridge_socket_env" \
      @RUNNER@ "$@"
  ) || runner_status=$?
fi
trace_wrapper "runner-exit:$runner_status"

if [ "$agent_session_mode" = "agent-exec" ]; then
  if [ -f "$host_exec_output_dir/stdout" ]; then
    cat "$host_exec_output_dir/stdout"
    trace_wrapper "agent-exec-stdout-present"
  fi
  if [ -f "$host_exec_output_dir/stderr" ]; then
    cat "$host_exec_output_dir/stderr" >&2
    trace_wrapper "agent-exec-stderr-present"
  fi

  if [ -f "$host_exec_output_dir/exit_code" ]; then
    IFS= read -r command_status < "$host_exec_output_dir/exit_code" || command_status=$runner_status
    trace_wrapper "agent-exec-exit-code:$command_status"
    if [ "$command_status" -ne 0 ] && [ -s "$runner_stderr_log" ]; then
      cat "$runner_stderr_log" >&2
    fi
    if [ "$command_status" -ne 0 ]; then
      if [ -s "$virtiofsd_hostcwd_log" ]; then
        cat "$virtiofsd_hostcwd_log" >&2
      fi
      if [ -s "$virtiofsd_agent_config_log" ]; then
        cat "$virtiofsd_agent_config_log" >&2
      fi
      if [ -s "$virtiofsd_agent_exec_log" ]; then
        cat "$virtiofsd_agent_exec_log" >&2
      fi
      if [ -s "$virtiofsd_worker_bridge_log" ]; then
        cat "$virtiofsd_worker_bridge_log" >&2
      fi
      if [ -s "$worker_bridge_server_log" ]; then
        cat "$worker_bridge_server_log" >&2
      fi
    fi
    exit "$command_status"
  fi
  trace_wrapper "agent-exec-exit-code-missing"

  if [ -s "$runner_stderr_log" ]; then
    cat "$runner_stderr_log" >&2
  fi
  if [ -s "$virtiofsd_hostcwd_log" ]; then
    cat "$virtiofsd_hostcwd_log" >&2
  fi
  if [ -s "$virtiofsd_agent_config_log" ]; then
    cat "$virtiofsd_agent_config_log" >&2
  fi
  if [ -s "$virtiofsd_agent_exec_log" ]; then
    cat "$virtiofsd_agent_exec_log" >&2
  fi
  if [ -s "$virtiofsd_worker_bridge_log" ]; then
    cat "$virtiofsd_worker_bridge_log" >&2
  fi
  if [ -s "$worker_bridge_server_log" ]; then
    cat "$worker_bridge_server_log" >&2
  fi
fi

if [ "$agent_session_mode" = "agent-attach-exec" ]; then
  if [ -f "$host_exec_output_dir/attach_stage" ]; then
    IFS= read -r attach_stage < "$host_exec_output_dir/attach_stage" || attach_stage=""
    if [ -n "$attach_stage" ]; then
      trace_wrapper "agent-attach-stage:$attach_stage"
    fi
  fi
  if [ -f "$host_exec_output_dir/exit_code" ]; then
    IFS= read -r command_status < "$host_exec_output_dir/exit_code" || command_status=$runner_status
    trace_wrapper "agent-attach-exit-code:$command_status"
    exit "$command_status"
  fi
  trace_wrapper "agent-attach-exit-code-missing"
fi

exit "$runner_status"
