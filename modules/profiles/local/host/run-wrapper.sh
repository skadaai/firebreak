set -eu

host_cwd=$PWD
host_uid=$(id -u)
host_gid=$(id -g)
agent_config_mode=${AGENT_CONFIG:-${CODEX_CONFIG:-vm}}
agent_session_mode=${AGENT_VM_ENTRYPOINT:-@DEFAULT_AGENT_SESSION_MODE@}
default_agent_command=@DEFAULT_AGENT_COMMAND@
agent_command_override=""
shell_command_override=${AGENT_VM_COMMAND:-}
agent_config_host_dir=""
host_runtime_dir=$(mktemp -d)
host_meta_dir=$host_runtime_dir/meta
host_exec_output_dir=$host_runtime_dir/exec-output
host_instance_dir=$host_runtime_dir/instance
runner_stdout_log=$host_runtime_dir/runner.stdout
runner_stderr_log=$host_runtime_dir/runner.stderr
virtiofsd_hostcwd_log=$host_runtime_dir/virtiofsd-hostcwd.log
virtiofsd_agent_config_log=$host_runtime_dir/virtiofsd-agent-config.log
virtiofsd_agent_exec_log=$host_runtime_dir/virtiofsd-agent-exec.log
hostcwd_socket=$host_runtime_dir/hostcwd.sock
agent_config_socket=$host_runtime_dir/agent-config.sock
agent_exec_output_socket=$host_runtime_dir/agent-exec-output.sock
default_control_socket=@CONTROL_SOCKET@
instance_state_dir=${FIREBREAK_INSTANCE_DIR:-}
instance_ephemeral=${FIREBREAK_INSTANCE_EPHEMERAL:-0}
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

reject_whitespace_path "$host_cwd" "current working directory"

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
fi

case "$agent_session_mode" in
  agent|shell)
    ;;
  *)
    echo "unsupported AGENT_VM_ENTRYPOINT: $agent_session_mode" >&2
    echo "supported values: agent, shell" >&2
    exit 1
    ;;
esac

if [ "$agent_session_mode" = "agent" ] && [ "$#" -gt 0 ]; then
  if [ -z "$default_agent_command" ]; then
    echo "this VM entrypoint does not support forwarding CLI arguments to an agent command" >&2
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
  host)
    agent_config_host_dir=$(resolve_host_dir "${AGENT_CONFIG_HOST_PATH:-${CODEX_CONFIG_HOST_PATH:-@DEFAULT_AGENT_CONFIG_HOST_DIR@}}")

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
  project|local)
    agent_config_mode=workspace
    ;;
  *)
    echo "unsupported AGENT_CONFIG mode: $agent_config_mode" >&2
    echo "supported modes: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

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
  rm -f "$control_socket"
  rm -rf "$host_runtime_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$host_meta_dir"
mkdir -p "$host_exec_output_dir"
rm -f "$control_socket"

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

if [ -n "$agent_config_host_dir" ]; then
  start_virtiofsd "$agent_config_host_dir" "$agent_config_socket" "$virtiofsd_agent_config_log"
  agent_config_virtiofsd_pid=$started_virtiofsd_pid
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
      MICROVM_AGENT_CONFIG_HOST_DIR="$agent_config_host_dir" \
      MICROVM_AGENT_CONFIG_HOST_SOCKET="$agent_config_socket" \
      MICROVM_AGENT_EXEC_OUTPUT_SOCKET="$agent_exec_output_socket" \
      @RUNNER@ "$@"
  ) >"$runner_stdout_log" 2>"$runner_stderr_log" || runner_status=$?
else
  (
    cd "$runner_workdir"
    env \
      MICROVM_HOST_META_DIR="$host_meta_dir" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_AGENT_CONFIG_HOST_DIR="$agent_config_host_dir" \
      MICROVM_AGENT_CONFIG_HOST_SOCKET="$agent_config_socket" \
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
      if [ -s "$virtiofsd_agent_config_log" ]; then
        cat "$virtiofsd_agent_config_log" >&2
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
  if [ -s "$virtiofsd_agent_config_log" ]; then
    cat "$virtiofsd_agent_config_log" >&2
  fi
  if [ -s "$virtiofsd_agent_exec_log" ]; then
    cat "$virtiofsd_agent_exec_log" >&2
  fi
fi

exit "$runner_status"
