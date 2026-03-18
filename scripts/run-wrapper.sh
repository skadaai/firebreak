set -eu

host_cwd=$PWD
host_uid=$(id -u)
host_gid=$(id -g)
codex_config_mode=${CODEX_CONFIG:-vm}
codex_config_host_dir=""
host_runtime_dir=$(mktemp -d)
host_meta_dir=$host_runtime_dir/meta
hostcwd_socket=$host_runtime_dir/hostcwd.sock
codex_config_socket=$host_runtime_dir/codex-config.sock

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

case "$codex_config_mode" in
  host)
    codex_config_host_dir=$(resolve_host_dir "${CODEX_CONFIG_HOST_PATH:-$HOME/.codex}")

    case "$codex_config_host_dir" in
      /*) ;;
      *)
        echo "CODEX_CONFIG_HOST_PATH must resolve to an absolute host path: $codex_config_host_dir" >&2
        exit 1
        ;;
    esac

    reject_whitespace_path "$codex_config_host_dir" "Codex host config path"

    mkdir -p "$codex_config_host_dir"
    ;;
  workspace|vm|fresh)
    ;;
  project|local)
    codex_config_mode=workspace
    ;;
  *)
    echo "unsupported CODEX_CONFIG mode: $codex_config_mode" >&2
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
  if [ -n "${codex_config_virtiofsd_pid:-}" ]; then
    kill "$codex_config_virtiofsd_pid" 2>/dev/null || true
    wait "$codex_config_virtiofsd_pid" 2>/dev/null || true
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
printf '%s\n' "$codex_config_mode" > "$host_meta_dir/codex-config-mode"

start_virtiofsd "$host_cwd" "$hostcwd_socket"
hostcwd_virtiofsd_pid=$started_virtiofsd_pid

if [ -n "$codex_config_host_dir" ]; then
  start_virtiofsd "$codex_config_host_dir" "$codex_config_socket"
  codex_config_virtiofsd_pid=$started_virtiofsd_pid
fi

env \
  MICROVM_HOST_META_DIR="$host_meta_dir" \
  MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
  MICROVM_CODEX_CONFIG_HOST_DIR="$codex_config_host_dir" \
  MICROVM_CODEX_CONFIG_HOST_SOCKET="$codex_config_socket" \
  @RUNNER@ "$@"
