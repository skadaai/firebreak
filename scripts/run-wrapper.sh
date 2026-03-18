set -eu

host_cwd=$PWD
host_uid=$(id -u)
host_gid=$(id -g)
agent_config_mode=${AGENT_CONFIG:-${CODEX_CONFIG:-vm}}
agent_session_mode=${AGENT_VM_ENTRYPOINT:-@DEFAULT_AGENT_SESSION_MODE@}
default_agent_command=@DEFAULT_AGENT_COMMAND@
agent_command_override=""
agent_config_host_dir=""
host_runtime_dir=$(mktemp -d)
host_meta_dir=$host_runtime_dir/meta
hostcwd_socket=$host_runtime_dir/hostcwd.sock
agent_config_socket=$host_runtime_dir/agent-config.sock

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

  agent_command_override=$default_agent_command
  for arg in "$@"; do
    printf -v quoted_arg '%q' "$arg"
    agent_command_override="$agent_command_override $quoted_arg"
  done
  set --
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

cleanup() {
  status=$?
  if [ -n "${hostcwd_virtiofsd_pid:-}" ]; then
    kill "$hostcwd_virtiofsd_pid" 2>/dev/null || true
    wait "$hostcwd_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${agent_config_virtiofsd_pid:-}" ]; then
    kill "$agent_config_virtiofsd_pid" 2>/dev/null || true
    wait "$agent_config_virtiofsd_pid" 2>/dev/null || true
  fi
  rm -rf "$host_runtime_dir"
  exit "$status"
}
trap cleanup EXIT INT TERM

mkdir -p "$host_meta_dir"

start_virtiofsd() {
  shared_dir=$1
  socket_path=$2
  virtiofsd \
    --socket-path="$socket_path" \
    --shared-dir="$shared_dir" \
    --sandbox=none \
    --posix-acl \
    --xattr &
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

start_virtiofsd "$host_cwd" "$hostcwd_socket"
hostcwd_virtiofsd_pid=$started_virtiofsd_pid

if [ -n "$agent_config_host_dir" ]; then
  start_virtiofsd "$agent_config_host_dir" "$agent_config_socket"
  agent_config_virtiofsd_pid=$started_virtiofsd_pid
fi

env \
  MICROVM_HOST_META_DIR="$host_meta_dir" \
  MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
  MICROVM_AGENT_CONFIG_HOST_DIR="$agent_config_host_dir" \
  MICROVM_AGENT_CONFIG_HOST_SOCKET="$agent_config_socket" \
  @RUNNER@ "$@"
