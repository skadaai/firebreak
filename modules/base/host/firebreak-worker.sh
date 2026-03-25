set -eu

state_dir=${FIREBREAK_WORKER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/worker-broker}
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker spawn --backend BACKEND --kind KIND [--workspace PATH] [--package NAME] [--vm-mode MODE] [--] COMMAND...
  firebreak worker list
  firebreak worker show --worker-id ID
  firebreak worker stop --worker-id ID
EOF
  exit 1
}

json_escape() {
  value=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  value=$(printf '%s' "$value" | tr '\n' ' ')
  printf '%s' "$value"
}

validate_token() {
  value=$1
  description=$2
  case "$value" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "$description must be a single path-safe token without whitespace: $value" >&2
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
      echo "$description must be an absolute path: $value" >&2
      exit 1
      ;;
  esac
}

worker_root_for_id() {
  printf '%s\n' "$state_dir/workers/$1"
}

write_metadata() {
  mkdir -p "$worker_root"
  printf '%s\n' "$worker_id" >"$worker_root/worker-id"
  printf '%s\n' "$backend" >"$worker_root/backend"
  printf '%s\n' "$kind" >"$worker_root/kind"
  printf '%s\n' "$workspace" >"$worker_root/workspace"
  printf '%s\n' "$created_at" >"$worker_root/created-at"
  printf '%s\n' "$status" >"$worker_root/status"
  printf '%s\n' "$pid" >"$worker_root/pid"
  printf '%s\n' "$stdout_path" >"$worker_root/stdout-path"
  printf '%s\n' "$stderr_path" >"$worker_root/stderr-path"
  if [ -n "$package_name" ]; then
    printf '%s\n' "$package_name" >"$worker_root/package-name"
  else
    rm -f "$worker_root/package-name"
  fi
  if [ -n "$vm_mode" ]; then
    printf '%s\n' "$vm_mode" >"$worker_root/vm-mode"
  else
    rm -f "$worker_root/vm-mode"
  fi
  if [ -n "$finished_at" ]; then
    printf '%s\n' "$finished_at" >"$worker_root/finished-at"
  else
    rm -f "$worker_root/finished-at"
  fi
  if [ -n "$exit_code" ]; then
    printf '%s\n' "$exit_code" >"$worker_root/exit-code"
  else
    rm -f "$worker_root/exit-code"
  fi
  if [ "$stop_requested" = "1" ]; then
    : >"$worker_root/stop-requested"
  else
    rm -f "$worker_root/stop-requested"
  fi

  cat >"$worker_root/metadata.json" <<EOF
{
  "worker_id": "$(json_escape "$worker_id")",
  "backend": "$(json_escape "$backend")",
  "kind": "$(json_escape "$kind")",
  "status": "$(json_escape "$status")",
  "workspace": "$(json_escape "$workspace")",
  "package_name": $(if [ -n "$package_name" ]; then printf '"%s"' "$(json_escape "$package_name")"; else printf 'null'; fi),
  "vm_mode": $(if [ -n "$vm_mode" ]; then printf '"%s"' "$(json_escape "$vm_mode")"; else printf 'null'; fi),
  "pid": $pid,
  "stdout_path": "$(json_escape "$stdout_path")",
  "stderr_path": "$(json_escape "$stderr_path")",
  "worker_root": "$(json_escape "$worker_root")",
  "created_at": "$(json_escape "$created_at")",
  "finished_at": $(if [ -n "$finished_at" ]; then printf '"%s"' "$(json_escape "$finished_at")"; else printf 'null'; fi),
  "exit_code": $(if [ -n "$exit_code" ]; then printf '%s' "$exit_code"; else printf 'null'; fi),
  "stop_requested": $([ "$stop_requested" = "1" ] && printf 'true' || printf 'false')
}
EOF
}

load_worker() {
  worker_id=$1
  validate_token "$worker_id" "worker id"
  worker_root=$(worker_root_for_id "$worker_id")

  if ! [ -f "$worker_root/metadata.json" ]; then
    echo "unknown worker id: $worker_id" >&2
    exit 1
  fi

  backend=$(cat "$worker_root/backend")
  kind=$(cat "$worker_root/kind")
  workspace=$(cat "$worker_root/workspace")
  created_at=$(cat "$worker_root/created-at")
  status=$(cat "$worker_root/status")
  pid=$(cat "$worker_root/pid")
  stdout_path=$(cat "$worker_root/stdout-path")
  stderr_path=$(cat "$worker_root/stderr-path")
  package_name=""
  vm_mode=""
  finished_at=""
  exit_code=""
  stop_requested=0
  if [ -f "$worker_root/package-name" ]; then
    package_name=$(cat "$worker_root/package-name")
  fi
  if [ -f "$worker_root/vm-mode" ]; then
    vm_mode=$(cat "$worker_root/vm-mode")
  fi
  if [ -f "$worker_root/finished-at" ]; then
    finished_at=$(cat "$worker_root/finished-at")
  fi
  if [ -f "$worker_root/exit-code" ]; then
    exit_code=$(cat "$worker_root/exit-code")
  fi
  if [ -f "$worker_root/stop-requested" ]; then
    stop_requested=1
  fi
}

refresh_worker_status() {
  worker_id=$1
  load_worker "$worker_id"

  if [ -f "$worker_root/exit-code" ]; then
    exit_code=$(cat "$worker_root/exit-code")
    if [ -f "$worker_root/finished-at" ]; then
      finished_at=$(cat "$worker_root/finished-at")
    fi
    if [ -z "$finished_at" ]; then
      finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    fi
    if [ "$stop_requested" = "1" ]; then
      status="stopped"
    else
      status="exited"
    fi
    write_metadata
    return 0
  fi

  if kill -0 "$pid" 2>/dev/null; then
    if [ "$stop_requested" = "1" ] && [ "$status" != "stopping" ]; then
      status="stopping"
      write_metadata
    fi
    return 0
  fi

  if [ -f "$worker_root/exit-code" ]; then
    exit_code=$(cat "$worker_root/exit-code")
  fi
  if [ -f "$worker_root/finished-at" ]; then
    finished_at=$(cat "$worker_root/finished-at")
  fi
  if [ -z "$finished_at" ]; then
    finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fi

  if [ "$stop_requested" = "1" ]; then
    status="stopped"
  else
    status="exited"
  fi
  write_metadata
}

quote_arg() {
  printf '%q' "$1"
}

write_process_launch_script() {
  launch_script=$1
  shift

  quoted_workspace=$(quote_arg "$workspace")
  quoted_stdout=$(quote_arg "$stdout_path")
  quoted_stderr=$(quote_arg "$stderr_path")
  quoted_exit_code=$(quote_arg "$worker_root/exit-code")
  quoted_finished_at=$(quote_arg "$worker_root/finished-at")
  quoted_child_pid=$(quote_arg "$worker_root/child-pid")

  quoted_command=""
  for arg in "$@"; do
    quoted_command="$quoted_command $(quote_arg "$arg")"
  done

  cat >"$launch_script" <<EOF
set -eu
workspace=$quoted_workspace
stdout_path=$quoted_stdout
stderr_path=$quoted_stderr
exit_code_path=$quoted_exit_code
finished_at_path=$quoted_finished_at
child_pid_path=$quoted_child_pid

finish() {
  status=\$1
  printf '%s\n' "\$status" >"\$exit_code_path"
  date -u +%Y-%m-%dT%H:%M:%SZ >"\$finished_at_path"
}

stop_child() {
  if [ -n "\${child_pid:-}" ]; then
    kill "\$child_pid" 2>/dev/null || true
    wait "\$child_pid" 2>/dev/null || true
  fi
  finish 143
  exit 143
}

trap stop_child INT TERM

cd "\$workspace"
exec 1>"\$stdout_path"
exec 2>"\$stderr_path"

set +e
$quoted_command &
child_pid=\$!
printf '%s\n' "\$child_pid" >"\$child_pid_path"
wait "\$child_pid"
command_status=\$?
set -e

finish "\$command_status"
exit "\$command_status"
EOF
}

write_firebreak_launch_script() {
  launch_script=$1
  shift

  if [ -z "${FIREBREAK_FLAKE_REF:-}" ]; then
    echo "FIREBREAK_FLAKE_REF is required for firebreak worker backend" >&2
    exit 1
  fi

  quoted_workspace=$(quote_arg "$workspace")
  quoted_stdout=$(quote_arg "$stdout_path")
  quoted_stderr=$(quote_arg "$stderr_path")
  quoted_exit_code=$(quote_arg "$worker_root/exit-code")
  quoted_finished_at=$(quote_arg "$worker_root/finished-at")
  quoted_child_pid=$(quote_arg "$worker_root/child-pid")
  quoted_instance_dir=$(quote_arg "$worker_root/instance")
  quoted_vm_mode=$(quote_arg "$vm_mode")
  quoted_installable=$(quote_arg "$FIREBREAK_FLAKE_REF#$package_name")

  nix_command="nix"
  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ]; then
    nix_command="$nix_command --accept-flake-config"
  fi
  if [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    nix_command="$nix_command --extra-experimental-features $(quote_arg "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES")"
  fi
  nix_command="$nix_command run $quoted_installable --"

  quoted_args=""
  for arg in "$@"; do
    quoted_args="$quoted_args $(quote_arg "$arg")"
  done

  cat >"$launch_script" <<EOF
set -eu
workspace=$quoted_workspace
stdout_path=$quoted_stdout
stderr_path=$quoted_stderr
exit_code_path=$quoted_exit_code
finished_at_path=$quoted_finished_at
child_pid_path=$quoted_child_pid
instance_dir=$quoted_instance_dir
vm_mode=$quoted_vm_mode

finish() {
  status=\$1
  printf '%s\n' "\$status" >"\$exit_code_path"
  date -u +%Y-%m-%dT%H:%M:%SZ >"\$finished_at_path"
}

stop_child() {
  if [ -n "\${child_pid:-}" ]; then
    kill "\$child_pid" 2>/dev/null || true
    wait "\$child_pid" 2>/dev/null || true
  fi
  finish 143
  exit 143
}

trap stop_child INT TERM

mkdir -p "\$instance_dir"
cd "\$workspace"
exec 1>"\$stdout_path"
exec 2>"\$stderr_path"

set +e
env FIREBREAK_INSTANCE_DIR="\$instance_dir" FIREBREAK_VM_MODE="\$vm_mode" $nix_command$quoted_args &
child_pid=\$!
printf '%s\n' "\$child_pid" >"\$child_pid_path"
wait "\$child_pid"
command_status=\$?
set -e

finish "\$command_status"
exit "\$command_status"
EOF
}

spawn_worker() {
  backend=""
  kind=""
  workspace=$PWD
  package_name=""
  vm_mode=run

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --backend)
        backend=$2
        shift 2
        ;;
      --kind)
        kind=$2
        shift 2
        ;;
      --workspace)
        workspace=$2
        shift 2
        ;;
      --package)
        package_name=$2
        shift 2
        ;;
      --vm-mode)
        vm_mode=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        ;;
      *)
        break
        ;;
    esac
  done

  if [ -z "$backend" ] || [ -z "$kind" ]; then
    usage
  fi
  validate_token "$kind" "worker kind"
  require_absolute_dir "$state_dir" "worker state dir"
  require_absolute_dir "$workspace" "worker workspace"

  case "$backend" in
    process)
      [ "$#" -gt 0 ] || {
        echo "process backend requires a command after '--'" >&2
        exit 1
      }
      ;;
    firebreak)
      [ -n "$package_name" ] || {
        echo "firebreak backend requires --package" >&2
        exit 1
      }
      validate_token "$package_name" "worker package name"
      case "$vm_mode" in
        run|shell) ;;
        *)
          echo "unsupported firebreak worker vm mode: $vm_mode" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "unsupported worker backend: $backend" >&2
      exit 1
      ;;
  esac

  mkdir -p "$state_dir/workers"
  created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  worker_suffix=$(printf '%s|%s|%s|%s\n' "$kind" "$backend" "$created_at" "$$" | sha256sum | cut -c1-12)
  worker_id=$kind-$worker_suffix
  worker_root=$(worker_root_for_id "$worker_id")
  mkdir -p "$worker_root"
  stdout_path=$worker_root/stdout.log
  stderr_path=$worker_root/stderr.log
  status="active"
  pid=0
  finished_at=""
  exit_code=""
  stop_requested=0
  : >"$stdout_path"
  : >"$stderr_path"

  launch_script=$worker_root/launch.sh
  case "$backend" in
    process)
      write_process_launch_script "$launch_script" "$@"
      ;;
    firebreak)
      mkdir -p "$worker_root/instance"
      write_firebreak_launch_script "$launch_script" "$@"
      ;;
  esac

  nohup bash "$launch_script" >/dev/null 2>&1 &
  pid=$!
  write_metadata
  cat "$worker_root/metadata.json"
}

list_workers() {
  mkdir -p "$state_dir/workers"
  first=1
  printf '[\n'
  for candidate_root in "$state_dir"/workers/*; do
    [ -d "$candidate_root" ] || continue
    worker_id=$(basename "$candidate_root")
    refresh_worker_status "$worker_id"
    if [ "$first" = "1" ]; then
      first=0
    else
      printf ',\n'
    fi
    cat "$candidate_root/metadata.json"
  done
  printf '\n]\n'
}

show_worker() {
  worker_id=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worker-id)
        worker_id=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  [ -n "$worker_id" ] || usage
  refresh_worker_status "$worker_id"
  cat "$(worker_root_for_id "$worker_id")/metadata.json"
}

stop_worker() {
  worker_id=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worker-id)
        worker_id=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  [ -n "$worker_id" ] || usage
  load_worker "$worker_id"

  stop_requested=1
  if kill -0 "$pid" 2>/dev/null; then
    status="stopping"
    write_metadata
    if [ -f "$worker_root/child-pid" ]; then
      child_pid=$(cat "$worker_root/child-pid")
      kill "$child_pid" 2>/dev/null || true
    fi
    kill "$pid"
  else
    refresh_worker_status "$worker_id"
  fi

  cat "$worker_root/metadata.json"
}

case "$command" in
  spawn)
    shift
    spawn_worker "$@"
    ;;
  list)
    shift
    [ "$#" -eq 0 ] || usage
    list_workers
    ;;
  show)
    shift
    show_worker "$@"
    ;;
  stop)
    shift
    stop_worker "$@"
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak worker subcommand: $command" >&2
    exit 1
    ;;
esac
