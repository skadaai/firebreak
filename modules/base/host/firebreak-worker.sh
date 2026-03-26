set -eu

state_dir=${FIREBREAK_WORKER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/worker-broker}
worker_authority=${FIREBREAK_WORKER_AUTHORITY:-host}
worker_allow_firebreak=${FIREBREAK_WORKER_ALLOW_FIREBREAK:-1}
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker run --backend BACKEND --kind KIND [--workspace PATH] [--package NAME] [--vm-mode MODE] [--attach] [--json] [--] COMMAND...
  firebreak worker ps [-a|--all] [--json]
  firebreak worker inspect WORKER_ID
  firebreak worker logs [--stdout|--stderr] [-f|--follow] WORKER_ID
  firebreak worker stop [--all] [--json] [WORKER_ID...]
  firebreak worker rm [--all] [--force] [--json] [WORKER_ID...]
  firebreak worker prune [--force] [--json]
EOF
  exit "${1:-1}"
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

worker_is_active_status() {
  case "$1" in
    active|running|stopping)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

worker_summary_json() {
  cat <<EOF
{
  "worker_id": "$(json_escape "$worker_id")",
  "authority": "$(json_escape "$worker_authority")",
  "backend": "$(json_escape "$backend")",
  "kind": "$(json_escape "$kind")",
  "status": "$(json_escape "$status")",
  "workspace": "$(json_escape "$workspace")",
  "package_name": $(if [ -n "$package_name" ]; then printf '"%s"' "$(json_escape "$package_name")"; else printf 'null'; fi),
  "vm_mode": $(if [ -n "$vm_mode" ]; then printf '"%s"' "$(json_escape "$vm_mode")"; else printf 'null'; fi),
  "pid": $pid,
  "created_at": "$(json_escape "$created_at")",
  "finished_at": $(if [ -n "$finished_at" ]; then printf '"%s"' "$(json_escape "$finished_at")"; else printf 'null'; fi),
  "exit_code": $(if [ -n "$exit_code" ]; then printf '%s' "$exit_code"; else printf 'null'; fi),
  "stop_requested": $([ "$stop_requested" = "1" ] && printf 'true' || printf 'false')
}
EOF
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
  "authority": "$(json_escape "$worker_authority")",
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
    elif [ "$status" = "active" ]; then
      status="running"
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
  attach_mode=$2
  shift 2

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
attach_mode=$attach_mode

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
if [ "\$attach_mode" = "1" ]; then
  exec > >(tee -a "\$stdout_path")
  exec 2> >(tee -a "\$stderr_path" >&2)
else
  exec 1>"\$stdout_path"
  exec 2>"\$stderr_path"
fi

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
  attach_mode=$2
  shift 2

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
attach_mode=$attach_mode

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
if [ "\$attach_mode" = "1" ]; then
  exec > >(tee -a "\$stdout_path")
  exec 2> >(tee -a "\$stderr_path" >&2)
else
  exec 1>"\$stdout_path"
  exec 2>"\$stderr_path"
fi

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
  attach_mode=0
  run_json=0
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
      --json)
        run_json=1
        shift
        ;;
      --attach)
        attach_mode=1
        shift
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
  if [ "$attach_mode" = "1" ] && [ "$run_json" = "1" ]; then
    echo "firebreak worker run does not support --attach with --json" >&2
    exit 1
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
      if [ "$worker_allow_firebreak" != "1" ]; then
        echo "firebreak backend is unavailable in this worker runtime" >&2
        exit 1
      fi
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
  status="running"
  pid=0
  finished_at=""
  exit_code=""
  stop_requested=0
  : >"$stdout_path"
  : >"$stderr_path"

  launch_script=$worker_root/launch.sh
  case "$backend" in
    process)
      write_process_launch_script "$launch_script" "$attach_mode" "$@"
      ;;
    firebreak)
      mkdir -p "$worker_root/instance"
      write_firebreak_launch_script "$launch_script" "$attach_mode" "$@"
      ;;
  esac

  if [ "$attach_mode" = "1" ]; then
    pid=$$
    write_metadata
    exec bash "$launch_script"
  fi

  nohup bash "$launch_script" >/dev/null 2>&1 &
  pid=$!
  write_metadata

  if [ "$run_json" = "1" ]; then
    cat "$worker_root/metadata.json"
  else
    printf '%s\n' "$worker_id"
  fi
}

for_each_worker() {
  mkdir -p "$state_dir/workers"
  for candidate_root in "$state_dir"/workers/*; do
    [ -d "$candidate_root" ] || continue
    worker_id=$(basename "$candidate_root")
    refresh_worker_status "$worker_id"
    "$@" "$worker_id"
  done
}

emit_ps_row() {
  worker_id=$1
  load_worker "$worker_id"
  exit_value=-
  if [ -n "$exit_code" ]; then
    exit_value=$exit_code
  fi
  printf '%-22s %-14s %-10s %-10s %-6s\n' "$worker_id" "$kind" "$backend" "$status" "$exit_value"
}

ps_workers() {
  ps_all=0
  ps_json=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -a|--all)
        ps_all=1
        shift
        ;;
      --json)
        ps_json=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ "$ps_json" = "1" ]; then
    first=1
    printf '[\n'
    for candidate_root in "$state_dir"/workers/*; do
      [ -d "$candidate_root" ] || continue
      worker_id=$(basename "$candidate_root")
      refresh_worker_status "$worker_id"
      load_worker "$worker_id"
      if [ "$ps_all" != "1" ] && ! worker_is_active_status "$status"; then
        continue
      fi
      if [ "$first" = "1" ]; then
        first=0
      else
        printf ',\n'
      fi
      worker_summary_json
    done
    printf '\n]\n'
    return 0
  fi

  printf '%-22s %-14s %-10s %-10s %-6s\n' "WORKER ID" "KIND" "BACKEND" "STATUS" "EXIT"
  for candidate_root in "$state_dir"/workers/*; do
    [ -d "$candidate_root" ] || continue
    worker_id=$(basename "$candidate_root")
    refresh_worker_status "$worker_id"
    load_worker "$worker_id"
    if [ "$ps_all" != "1" ] && ! worker_is_active_status "$status"; then
      continue
    fi
    emit_ps_row "$worker_id"
  done
}

inspect_worker() {
  [ "$#" -eq 1 ] || usage
  refresh_worker_status "$1"
  cat "$(worker_root_for_id "$1")/metadata.json"
}

logs_worker() {
  logs_stdout=1
  logs_follow=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --stdout)
        logs_stdout=1
        shift
        ;;
      --stderr)
        logs_stdout=0
        shift
        ;;
      -f|--follow)
        logs_follow=1
        shift
        ;;
      -*)
        usage
        ;;
      *)
        break
        ;;
    esac
  done

  [ "$#" -eq 1 ] || usage
  load_worker "$1"

  if [ "$logs_follow" = "1" ]; then
    if [ "$logs_stdout" = "1" ]; then
      exec tail -n +1 -f "$stdout_path"
    fi
    exec tail -n +1 -f "$stderr_path"
  fi

  if [ "$logs_stdout" = "1" ]; then
    cat "$stdout_path"
  else
    cat "$stderr_path"
  fi
}

stop_one_worker() {
  worker_id=$1
  refresh_worker_status "$worker_id"
  load_worker "$worker_id"

  stop_requested=1
  if kill -0 "$pid" 2>/dev/null; then
    status="stopping"
    write_metadata
    if [ -f "$worker_root/child-pid" ]; then
      child_pid=$(cat "$worker_root/child-pid")
      kill "$child_pid" 2>/dev/null || true
    fi
    kill "$pid" 2>/dev/null || true
  else
    refresh_worker_status "$worker_id"
  fi
}

emit_json_array_from_worker_ids() {
  first=1
  printf '[\n'
  for worker_id in "$@"; do
    if [ "$first" = "1" ]; then
      first=0
    else
      printf ',\n'
    fi
    cat "$(worker_root_for_id "$worker_id")/metadata.json"
  done
  printf '\n]\n'
}

stop_worker() {
  stop_all=0
  stop_json=0
  stop_ids=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all)
        stop_all=1
        shift
        ;;
      --json)
        stop_json=1
        shift
        ;;
      -*)
        usage
        ;;
      *)
        validate_token "$1" "worker id"
        stop_ids+=("$1")
        shift
        ;;
    esac
  done

  if [ "$stop_all" = "1" ] && [ "${#stop_ids[@]}" -gt 0 ]; then
    usage
  fi
  if [ "$stop_all" != "1" ] && [ "${#stop_ids[@]}" -eq 0 ]; then
    usage
  fi

  if [ "$stop_all" = "1" ]; then
    stop_ids=()
    for candidate_root in "$state_dir"/workers/*; do
      [ -d "$candidate_root" ] || continue
      worker_id=$(basename "$candidate_root")
      refresh_worker_status "$worker_id"
      load_worker "$worker_id"
      if worker_is_active_status "$status"; then
        stop_ids+=("$worker_id")
      fi
    done
  fi

  [ "${#stop_ids[@]}" -gt 0 ] || {
    if [ "$stop_json" = "1" ]; then
      printf '%s\n' '[]'
    fi
    return 0
  }

  for worker_id in "${stop_ids[@]}"; do
    stop_one_worker "$worker_id"
  done

  if [ "$stop_json" = "1" ]; then
    if [ "${#stop_ids[@]}" -eq 1 ] && [ "$stop_all" != "1" ]; then
      cat "$(worker_root_for_id "${stop_ids[0]}")/metadata.json"
    else
      emit_json_array_from_worker_ids "${stop_ids[@]}"
    fi
  else
    for worker_id in "${stop_ids[@]}"; do
      printf '%s\n' "$worker_id"
    done
  fi
}

wait_until_worker_stops() {
  target_worker_id=$1
  for _ in $(seq 1 300); do
    refresh_worker_status "$target_worker_id"
    load_worker "$target_worker_id"
    if ! worker_is_active_status "$status"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

remove_one_worker() {
  target_worker_id=$1
  remove_force=$2

  refresh_worker_status "$target_worker_id"
  load_worker "$target_worker_id"

  if worker_is_active_status "$status"; then
    if [ "$remove_force" != "1" ]; then
      echo "worker is still running: $target_worker_id" >&2
      exit 1
    fi
    stop_one_worker "$target_worker_id"
    if ! wait_until_worker_stops "$target_worker_id"; then
      echo "timed out waiting for worker to stop before removal: $target_worker_id" >&2
      exit 1
    fi
    load_worker "$target_worker_id"
  fi

  removed_metadata=$(cat "$worker_root/metadata.json")
  rm -rf "$worker_root"
  printf '%s\n' "$removed_metadata"
}

rm_worker() {
  rm_all=0
  rm_force=0
  rm_json=0
  rm_ids=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --all)
        rm_all=1
        shift
        ;;
      --force)
        rm_force=1
        shift
        ;;
      --json)
        rm_json=1
        shift
        ;;
      -*)
        usage
        ;;
      *)
        validate_token "$1" "worker id"
        rm_ids+=("$1")
        shift
        ;;
    esac
  done

  if [ "$rm_all" = "1" ] && [ "${#rm_ids[@]}" -gt 0 ]; then
    usage
  fi
  if [ "$rm_all" != "1" ] && [ "${#rm_ids[@]}" -eq 0 ]; then
    usage
  fi

  if [ "$rm_all" = "1" ]; then
    rm_ids=()
    for candidate_root in "$state_dir"/workers/*; do
      [ -d "$candidate_root" ] || continue
      worker_id=$(basename "$candidate_root")
      rm_ids+=("$worker_id")
    done
  fi

  first=1
  if [ "$rm_json" = "1" ] && ! { [ "$rm_all" != "1" ] && [ "${#rm_ids[@]}" -eq 1 ]; }; then
    printf '[\n'
  fi

  for worker_id in "${rm_ids[@]}"; do
    removed_metadata=$(remove_one_worker "$worker_id" "$rm_force")
    if [ "$rm_json" = "1" ]; then
      if [ "${#rm_ids[@]}" -eq 1 ] && [ "$rm_all" != "1" ]; then
        printf '%s\n' "$removed_metadata"
      else
        if [ "$first" = "1" ]; then
          first=0
        else
          printf ',\n'
        fi
        printf '%s' "$removed_metadata"
      fi
    else
      printf '%s\n' "$worker_id"
    fi
  done

  if [ "$rm_json" = "1" ] && ! { [ "$rm_all" != "1" ] && [ "${#rm_ids[@]}" -eq 1 ]; }; then
    printf '\n]\n'
  fi
}

prune_workers() {
  prune_force=0
  prune_json=0
  prune_ids=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force)
        prune_force=1
        shift
        ;;
      --json)
        prune_json=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done

  for candidate_root in "$state_dir"/workers/*; do
    [ -d "$candidate_root" ] || continue
    worker_id=$(basename "$candidate_root")
    refresh_worker_status "$worker_id"
    load_worker "$worker_id"
    if worker_is_active_status "$status"; then
      if [ "$prune_force" = "1" ]; then
        prune_ids+=("$worker_id")
      fi
    else
      prune_ids+=("$worker_id")
    fi
  done

  if [ "${#prune_ids[@]}" -eq 0 ]; then
    if [ "$prune_json" = "1" ]; then
      printf '%s\n' '[]'
    fi
    return 0
  fi

  prune_args=()
  if [ "$prune_force" = "1" ]; then
    prune_args+=(--force)
  fi
  if [ "$prune_json" = "1" ]; then
    prune_args+=(--json)
  fi
  rm_worker "${prune_args[@]}" "${prune_ids[@]}"
}

case "$command" in
  run)
    shift
    spawn_worker "$@"
    ;;
  ps)
    shift
    ps_workers "$@"
    ;;
  inspect)
    shift
    inspect_worker "$@"
    ;;
  logs)
    shift
    logs_worker "$@"
    ;;
  stop)
    shift
    stop_worker "$@"
    ;;
  rm)
    shift
    rm_worker "$@"
    ;;
  prune)
    shift
    prune_workers "$@"
    ;;
  ""|--help|-h|help)
    usage 0
    ;;
  *)
    echo "unknown firebreak worker subcommand: $command" >&2
    exit 1
    ;;
esac
