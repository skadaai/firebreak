#!/usr/bin/env bash
set -eu

firebreak_libexec_dir=${FIREBREAK_LIBEXEC_DIR:-}
if [ -z "$firebreak_libexec_dir" ]; then
  firebreak_libexec_dir=$(
    CDPATH='' cd -- "$(dirname -- "$0")" && pwd
  )
fi

# shellcheck disable=SC1091
. "$firebreak_libexec_dir/firebreak-project-config.sh"

state_dir=${FIREBREAK_WORKER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/worker-broker}
worker_authority=${FIREBREAK_WORKER_AUTHORITY:-host}
worker_allow_firebreak=${FIREBREAK_WORKER_ALLOW_FIREBREAK:-1}
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker run --backend BACKEND --kind KIND [--workspace PATH] [--package NAME] [--launch-mode MODE] [--max-instances COUNT] [--attach] [--json] [--] COMMAND...
  firebreak worker ps [-a|--all] [--json]
  firebreak worker inspect WORKER_ID
  firebreak worker logs [--stdout|--stderr] [-f|--follow] WORKER_ID
  firebreak worker debug [--json]
  firebreak worker stop [--all] [--json] [WORKER_ID...]
  firebreak worker rm [--all] [--force] [--json] [WORKER_ID...]
  firebreak worker prune [--force] [--json]
EOF
  exit "${1:-1}"
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read())[1:-1], end="")'
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

validate_positive_integer() {
  value=$1
  description=$2

  case "$value" in
    ""|*[!0-9]*)
      echo "$description must be a positive integer: $value" >&2
      exit 1
      ;;
  esac

  if [ "$value" -le 0 ]; then
    echo "$description must be greater than zero: $value" >&2
    exit 1
  fi
}

worker_root_for_id() {
  printf '%s\n' "$state_dir/workers/$1"
}

read_host_boot_id() {
  host_boot_id=""
  if [ -r /proc/sys/kernel/random/boot_id ]; then
    IFS= read -r host_boot_id </proc/sys/kernel/random/boot_id || host_boot_id=""
  fi
  printf '%s\n' "$host_boot_id"
}

read_process_state() {
  target_pid=$1
  TARGET_PID=$target_pid python3 - <<'PY'
import os
import sys

path = f"/proc/{os.environ['TARGET_PID']}/stat"
try:
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read().strip()
except OSError:
    raise SystemExit(1)

rparen = text.rfind(")")
if rparen == -1:
    raise SystemExit(1)

rest = text[rparen + 2 :].split()
if not rest:
    raise SystemExit(1)

print(rest[0])
PY
}

read_process_start_time() {
  target_pid=$1
  TARGET_PID=$target_pid python3 - <<'PY'
import os
import sys

path = f"/proc/{os.environ['TARGET_PID']}/stat"
try:
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read().strip()
except OSError:
    raise SystemExit(1)

rparen = text.rfind(")")
if rparen == -1:
    raise SystemExit(1)

rest = text[rparen + 2 :].split()
if len(rest) < 20:
    raise SystemExit(1)

print(rest[19])
PY
}

capture_process_identity() {
  target_pid=$1
  captured_process_boot_id=$(read_host_boot_id)
  captured_process_start_time=""

  for _ in $(seq 1 10); do
    captured_process_start_time=$(read_process_start_time "$target_pid" 2>/dev/null || true)
    if [ -n "$captured_process_start_time" ]; then
      break
    fi
    sleep 0.1
  done
}

process_matches_identity() {
  target_pid=$1
  expected_boot_id=${2:-}
  expected_start_time=${3:-}

  if [ -z "$expected_boot_id" ] || [ -z "$expected_start_time" ]; then
    return 1
  fi

  current_boot_id=$(read_host_boot_id)
  if [ -z "$current_boot_id" ] || [ "$current_boot_id" != "$expected_boot_id" ]; then
    return 1
  fi

  current_start_time=$(read_process_start_time "$target_pid" 2>/dev/null || true)
  if [ -z "$current_start_time" ] || [ "$current_start_time" != "$expected_start_time" ]; then
    return 1
  fi

  return 0
}

process_is_alive() {
  target_pid=$1
  expected_boot_id=${2:-}
  expected_start_time=${3:-}

  if ! process_matches_identity "$target_pid" "$expected_boot_id" "$expected_start_time"; then
    return 1
  fi

  if ! kill -0 "$target_pid" 2>/dev/null; then
    return 1
  fi

  process_state=$(read_process_state "$target_pid" 2>/dev/null || true)
  if [ "$process_state" = "Z" ]; then
    return 1
  fi

  return 0
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

count_active_workers_for_scope() {
  target_kind=$1
  target_scope=$2
  active_count=0

  mkdir -p "$state_dir/workers"
  for candidate_root in "$state_dir"/workers/*; do
    [ -d "$candidate_root" ] || continue
    candidate_worker_id=$(basename "$candidate_root")
    refresh_worker_status "$candidate_worker_id"
    load_worker "$candidate_worker_id"
    if [ "$kind" = "$target_kind" ] && [ "$worker_limit_scope" = "$target_scope" ] && worker_is_active_status "$status"; then
      active_count=$((active_count + 1))
    fi
  done

  printf '%s\n' "$active_count"
}

worker_limit_lock_name() {
  kind_name=$1
  scope_name=$2
  lock_scope_hash=$(printf '%s|%s\n' "$kind_name" "$scope_name" | sha256sum | cut -c1-16)
  printf '%s-%s\n' "$kind_name" "$lock_scope_hash"
}

remove_kind_limit_lock_dir() {
  target_lock_dir=$1
  removal_dir=$target_lock_dir.removing.${BASHPID:-$$}

  rm -rf "$removal_dir"
  if mv -T "$target_lock_dir" "$removal_dir" 2>/dev/null; then
    rm -rf "$removal_dir"
    return 0
  fi

  return 1
}

acquire_kind_limit_lock() {
  kind_name=$1
  scope_name=$2
  lock_root=$state_dir/kind-locks
  lock_name=$(worker_limit_lock_name "$kind_name" "$scope_name")
  kind_limit_lock_dir=$lock_root/$lock_name.lock
  kind_limit_lock_owned=0
  current_boot_id=$(read_host_boot_id)

  mkdir -p "$lock_root"
  while :; do
    kind_limit_lock_temp_dir=$kind_limit_lock_dir.tmp.${BASHPID:-$$}
    rm -rf "$kind_limit_lock_temp_dir"

    if mkdir "$kind_limit_lock_temp_dir" 2>/dev/null; then
      printf '%s\n' "${BASHPID:-$$}" >"$kind_limit_lock_temp_dir/pid"
      if [ -n "$current_boot_id" ]; then
        printf '%s\n' "$current_boot_id" >"$kind_limit_lock_temp_dir/boot-id"
      fi
      date +%s >"$kind_limit_lock_temp_dir/acquired-at"
      if mv -T "$kind_limit_lock_temp_dir" "$kind_limit_lock_dir" 2>/dev/null; then
        kind_limit_lock_temp_dir=""
        kind_limit_lock_owned=1
        return 0
      fi
    fi
    rm -rf "$kind_limit_lock_temp_dir"
    kind_limit_lock_temp_dir=""

    stale_lock_pid=""
    stale_lock_boot_id=""
    if [ -r "$kind_limit_lock_dir/pid" ]; then
      IFS= read -r stale_lock_pid <"$kind_limit_lock_dir/pid" || stale_lock_pid=""
    fi
    if [ -r "$kind_limit_lock_dir/boot-id" ]; then
      IFS= read -r stale_lock_boot_id <"$kind_limit_lock_dir/boot-id" || stale_lock_boot_id=""
    fi

    if [ -n "$current_boot_id" ] && [ -z "$stale_lock_boot_id" ]; then
      remove_kind_limit_lock_dir "$kind_limit_lock_dir" || true
      continue
    fi

    if [ -n "$current_boot_id" ] && [ -n "$stale_lock_boot_id" ] && [ "$stale_lock_boot_id" != "$current_boot_id" ]; then
      remove_kind_limit_lock_dir "$kind_limit_lock_dir" || true
      continue
    fi

    if [ -n "$stale_lock_pid" ] && ! kill -0 "$stale_lock_pid" 2>/dev/null; then
      remove_kind_limit_lock_dir "$kind_limit_lock_dir" || true
      continue
    fi

    sleep 0.1
  done
}

release_kind_limit_lock() {
  if [ -n "${kind_limit_lock_temp_dir:-}" ]; then
    rm -rf "$kind_limit_lock_temp_dir"
    kind_limit_lock_temp_dir=""
  fi

  if [ "${kind_limit_lock_owned:-0}" = "1" ] && [ -n "${kind_limit_lock_dir:-}" ]; then
    remove_kind_limit_lock_dir "$kind_limit_lock_dir" || true
    kind_limit_lock_dir=""
    kind_limit_lock_owned=0
  fi
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
  "launch_mode": $(if [ -n "$launch_mode" ]; then printf '"%s"' "$(json_escape "$launch_mode")"; else printf 'null'; fi),
  "pid": $pid,
  "pid_boot_id": $(if [ -n "$pid_boot_id" ]; then printf '"%s"' "$(json_escape "$pid_boot_id")"; else printf 'null'; fi),
  "pid_start_time": $(if [ -n "$pid_start_time" ]; then printf '"%s"' "$(json_escape "$pid_start_time")"; else printf 'null'; fi),
  "flake_ref": $(if [ -n "$flake_ref" ]; then printf '"%s"' "$(json_escape "$flake_ref")"; else printf 'null'; fi),
  "trace_path": "$(json_escape "$trace_path")",
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
  if [ -n "$pid_boot_id" ]; then
    printf '%s\n' "$pid_boot_id" >"$worker_root/pid-boot-id"
  else
    rm -f "$worker_root/pid-boot-id"
  fi
  if [ -n "$pid_start_time" ]; then
    printf '%s\n' "$pid_start_time" >"$worker_root/pid-start-time"
  else
    rm -f "$worker_root/pid-start-time"
  fi
  printf '%s\n' "$stdout_path" >"$worker_root/stdout-path"
  printf '%s\n' "$stderr_path" >"$worker_root/stderr-path"
  printf '%s\n' "$trace_path" >"$worker_root/trace-path"
  if [ -n "${bridge_request_dir:-}" ]; then
    printf '%s\n' "$bridge_request_dir" >"$worker_root/bridge-request-dir"
  else
    rm -f "$worker_root/bridge-request-dir"
  fi
  if [ -n "${bridge_request_trace_path:-}" ]; then
    printf '%s\n' "$bridge_request_trace_path" >"$worker_root/bridge-request-trace-path"
  else
    rm -f "$worker_root/bridge-request-trace-path"
  fi
  if [ -n "$package_name" ]; then
    printf '%s\n' "$package_name" >"$worker_root/package-name"
  else
    rm -f "$worker_root/package-name"
  fi
  if [ -n "$launch_mode" ]; then
    printf '%s\n' "$launch_mode" >"$worker_root/launch-mode"
  else
    rm -f "$worker_root/launch-mode"
  fi
  if [ -n "$flake_ref" ]; then
    printf '%s\n' "$flake_ref" >"$worker_root/flake-ref"
  else
    rm -f "$worker_root/flake-ref"
  fi
  if [ -n "$worker_limit_scope" ]; then
    printf '%s\n' "$worker_limit_scope" >"$worker_root/worker-limit-scope"
  else
    rm -f "$worker_root/worker-limit-scope"
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

  emit_metadata_json >"$worker_root/metadata.json"
}

emit_metadata_json() {
  WORKER_ID=$worker_id \
  WORKER_AUTHORITY=$worker_authority \
  WORKER_BACKEND=$backend \
  WORKER_KIND=$kind \
  WORKER_STATUS=$status \
  WORKER_WORKSPACE=$workspace \
  WORKER_PACKAGE_NAME=$package_name \
  WORKER_LAUNCH_MODE=$launch_mode \
  WORKER_PID=$pid \
  WORKER_PID_BOOT_ID=$pid_boot_id \
  WORKER_PID_START_TIME=$pid_start_time \
  WORKER_FLAKE_REF=$flake_ref \
  WORKER_STDOUT_PATH=$stdout_path \
  WORKER_STDERR_PATH=$stderr_path \
  WORKER_TRACE_PATH=$trace_path \
  WORKER_BRIDGE_REQUEST_DIR=${bridge_request_dir:-} \
  WORKER_BRIDGE_REQUEST_TRACE_PATH=${bridge_request_trace_path:-} \
  WORKER_ROOT=$worker_root \
  WORKER_CREATED_AT=$created_at \
  WORKER_FINISHED_AT=$finished_at \
  WORKER_EXIT_CODE=$exit_code \
  WORKER_STOP_REQUESTED=$stop_requested \
  python3 - <<'PY'
import json
import os
import sys


def optional_text(name: str):
    value = os.environ.get(name, "")
    return value if value else None


def optional_int(name: str):
    value = os.environ.get(name, "")
    return int(value) if value else None


data = {
    "worker_id": os.environ["WORKER_ID"],
    "authority": os.environ["WORKER_AUTHORITY"],
    "backend": os.environ["WORKER_BACKEND"],
    "kind": os.environ["WORKER_KIND"],
    "status": os.environ["WORKER_STATUS"],
    "workspace": os.environ["WORKER_WORKSPACE"],
    "package_name": optional_text("WORKER_PACKAGE_NAME"),
    "launch_mode": optional_text("WORKER_LAUNCH_MODE"),
    "pid": int(os.environ["WORKER_PID"]),
    "pid_boot_id": optional_text("WORKER_PID_BOOT_ID"),
    "pid_start_time": optional_text("WORKER_PID_START_TIME"),
    "flake_ref": optional_text("WORKER_FLAKE_REF"),
    "stdout_path": os.environ["WORKER_STDOUT_PATH"],
    "stderr_path": os.environ["WORKER_STDERR_PATH"],
    "trace_path": os.environ["WORKER_TRACE_PATH"],
    "bridge_request_dir": optional_text("WORKER_BRIDGE_REQUEST_DIR"),
    "bridge_request_trace_path": optional_text("WORKER_BRIDGE_REQUEST_TRACE_PATH"),
    "worker_root": os.environ["WORKER_ROOT"],
    "created_at": os.environ["WORKER_CREATED_AT"],
    "finished_at": optional_text("WORKER_FINISHED_AT"),
    "exit_code": optional_int("WORKER_EXIT_CODE"),
    "stop_requested": os.environ.get("WORKER_STOP_REQUESTED") == "1",
}

json.dump(data, sys.stdout)
sys.stdout.write("\n")
PY
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
  pid_boot_id=""
  pid_start_time=""
  stdout_path=$(cat "$worker_root/stdout-path")
  stderr_path=$(cat "$worker_root/stderr-path")
  trace_path=$worker_root/trace.log
  if [ -f "$worker_root/trace-path" ]; then
    trace_path=$(cat "$worker_root/trace-path")
  fi
  bridge_request_dir=""
  bridge_request_trace_path=""
  package_name=""
  launch_mode=""
  flake_ref=""
  worker_limit_scope=""
  finished_at=""
  exit_code=""
  stop_requested=0
  if [ -f "$worker_root/pid-boot-id" ]; then
    pid_boot_id=$(cat "$worker_root/pid-boot-id")
  fi
  if [ -f "$worker_root/pid-start-time" ]; then
    pid_start_time=$(cat "$worker_root/pid-start-time")
  fi
  if [ -f "$worker_root/package-name" ]; then
    package_name=$(cat "$worker_root/package-name")
  fi
  if [ -f "$worker_root/bridge-request-dir" ]; then
    bridge_request_dir=$(cat "$worker_root/bridge-request-dir")
  fi
  if [ -f "$worker_root/bridge-request-trace-path" ]; then
    bridge_request_trace_path=$(cat "$worker_root/bridge-request-trace-path")
  fi
  if [ -f "$worker_root/launch-mode" ]; then
    launch_mode=$(cat "$worker_root/launch-mode")
  fi
  if [ -f "$worker_root/flake-ref" ]; then
    flake_ref=$(cat "$worker_root/flake-ref")
  fi
  if [ -f "$worker_root/worker-limit-scope" ]; then
    worker_limit_scope=$(cat "$worker_root/worker-limit-scope")
  elif [ "$backend" = "process" ]; then
    worker_limit_scope="process"
  elif [ "$backend" = "firebreak" ] && [ -n "$flake_ref" ]; then
    worker_limit_scope="firebreak:$flake_ref"
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
  persist_changes=${2:-1}
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
    if [ "$persist_changes" = "1" ]; then
      write_metadata
    fi
    return 0
  fi

  if [ -f "$worker_root/bridge-request-response-exit-code" ]; then
    exit_code=$(cat "$worker_root/bridge-request-response-exit-code")
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
    if [ "$persist_changes" = "1" ]; then
      write_metadata
    fi
    return 0
  fi

  if process_is_alive "$pid" "$pid_boot_id" "$pid_start_time"; then
    if [ "$stop_requested" = "1" ] && [ "$status" != "stopping" ]; then
      status="stopping"
      if [ "$persist_changes" = "1" ]; then
        write_metadata
      fi
    elif [ "$status" = "active" ]; then
      status="running"
      if [ "$persist_changes" = "1" ]; then
        write_metadata
      fi
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
  if [ "$persist_changes" = "1" ]; then
    write_metadata
  fi
}

quote_arg() {
  printf '%q' "$1"
}

firebreak_worker_maybe_print_flake_config_hint() {
  stderr_log=$1

  if grep -F -q "Pass '--accept-flake-config' to trust it" "$stderr_log" 2>/dev/null \
    || grep -F -q "untrusted flake configuration setting" "$stderr_log" 2>/dev/null; then
    cat >&2 <<'EOF'
firebreak worker: Nix refused this flake's configuration while resolving the nested Firebreak package.
Rerun with:
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run ...

If you are invoking the worker from a Firebreak-managed environment, export:
  FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1
EOF
  fi
}

firebreak_worker_capture_nix_stdout() {
  stderr_log=$(mktemp "${TMPDIR:-/tmp}/firebreak-worker-nix-stderr.XXXXXX")
  if output=$("$@" 2>"$stderr_log"); then
    status=0
  else
    status=$?
  fi
  if [ -s "$stderr_log" ]; then
    cat "$stderr_log" >&2
  fi
  if [ "$status" -eq 0 ]; then
    rm -f "$stderr_log"
    printf '%s\n' "$output"
    return 0
  fi
  firebreak_worker_maybe_print_flake_config_hint "$stderr_log"
  rm -f "$stderr_log"
  return "$status"
}

configure_attach_tty() {
  attach_tty_state=""
  if [ -t 0 ] && [ -t 1 ] && command -v stty >/dev/null 2>&1; then
    attach_tty_state=$(stty -g 2>/dev/null || true)
    stty raw -echo min 1 time 0 2>/dev/null || true
  fi
}

restore_attach_tty() {
  if [ -n "${attach_tty_state:-}" ]; then
    stty "$attach_tty_state" 2>/dev/null || true
    attach_tty_state=""
  fi
}

resolve_firebreak_worker_exec() {
  installable=$1
  package_name=$2

  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ] \
    && [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    build_output=$(firebreak_worker_capture_nix_stdout \
      nix --accept-flake-config \
        --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" \
        build --no-link --print-out-paths "$installable"
    )
  elif [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ]; then
    build_output=$(firebreak_worker_capture_nix_stdout \
      nix --accept-flake-config \
        build --no-link --print-out-paths "$installable"
    )
  elif [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    build_output=$(firebreak_worker_capture_nix_stdout \
      nix --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" \
        build --no-link --print-out-paths "$installable"
    )
  else
    build_output=$(firebreak_worker_capture_nix_stdout nix build --no-link --print-out-paths "$installable")
  fi

  resolved_out=$(printf '%s\n' "$build_output" | tail -n 1)
  if [ -z "$resolved_out" ] || ! [ -d "$resolved_out" ]; then
    echo "failed to resolve worker package output for $installable" >&2
    exit 1
  fi

  resolved_exec=$resolved_out/bin/$package_name
  if [ -x "$resolved_exec" ]; then
    printf '%s\n' "$resolved_exec"
    return 0
  fi

  resolved_exec=$(find "$resolved_out/bin" -maxdepth 1 -type f -perm -u+x 2>/dev/null | sort | head -n 1)
  if [ -n "$resolved_exec" ] && [ -x "$resolved_exec" ]; then
    printf '%s\n' "$resolved_exec"
    return 0
  fi

  echo "failed to resolve worker executable under $resolved_out/bin" >&2
  exit 1
}

write_process_launch_script() {
  launch_script=$1
  attach_mode=$2
  shift 2

  quoted_workspace=$(quote_arg "$workspace")
  quoted_stdout=$(quote_arg "$stdout_path")
  quoted_stderr=$(quote_arg "$stderr_path")
  quoted_trace=$(quote_arg "$trace_path")
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
trace_path=$quoted_trace
exit_code_path=$quoted_exit_code
finished_at_path=$quoted_finished_at
child_pid_path=$quoted_child_pid
attach_mode=$attach_mode

finish() {
  status=\$1
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "command-exit:\$status" >>"\$trace_path"
  printf '%s\n' "\$status" >"\$exit_code_path"
  date -u +%Y-%m-%dT%H:%M:%SZ >"\$finished_at_path"
}

stop_child() {
  if [ -z "\${child_pid:-}" ] && [ -r "\$child_pid_path" ]; then
    child_pid=\$(cat "\$child_pid_path" 2>/dev/null || true)
  fi
  if [ -n "\${child_pid:-}" ]; then
    kill "\$child_pid" 2>/dev/null || true
    wait "\$child_pid" 2>/dev/null || true
  fi
  finish 143
  exit 143
}

trap stop_child INT TERM

printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "launch-script-start" >>"\$trace_path"
cd "\$workspace"
if [ "\$attach_mode" != "1" ]; then
  exec 1>"\$stdout_path"
  exec 2>"\$stderr_path"
fi

set +e
if [ "\$attach_mode" = "1" ]; then
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "attach-foreground-start" >>"\$trace_path"
  bash -c '
    child_pid_path=\$1
    shift
    printf "%s\n" "\$BASHPID" >"\$child_pid_path"
    exec "\$@"
  ' bash "\$child_pid_path" $quoted_command
  command_status=\$?
else
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "detached-background-start" >>"\$trace_path"
  $quoted_command &
  child_pid=\$!
  printf '%s\n' "\$child_pid" >"\$child_pid_path"
  wait "\$child_pid"
  command_status=\$?
fi
set -e

finish "\$command_status"
exit "\$command_status"
EOF
}

write_firebreak_launch_script() {
  launch_script=$1
  attach_mode=$2
  shift 2
  forwarded_arg_count=$#

  if [ -z "${FIREBREAK_FLAKE_REF:-}" ]; then
    echo "FIREBREAK_FLAKE_REF is required for firebreak worker backend" >&2
    exit 1
  fi

  quoted_workspace=$(quote_arg "$workspace")
  quoted_stdout=$(quote_arg "$stdout_path")
  quoted_stderr=$(quote_arg "$stderr_path")
  quoted_trace=$(quote_arg "$trace_path")
  quoted_exit_code=$(quote_arg "$worker_root/exit-code")
  quoted_finished_at=$(quote_arg "$worker_root/finished-at")
  quoted_child_pid=$(quote_arg "$worker_root/child-pid")
  quoted_instance_dir=$(quote_arg "$worker_root/instance")
  quoted_launch_mode=$(quote_arg "$launch_mode")
  resolved_exec=$(resolve_firebreak_worker_exec "$FIREBREAK_FLAKE_REF#$package_name" "$package_name")
  quoted_resolved_exec=$(quote_arg "$resolved_exec")

  quoted_unset_env_args=""
  while IFS= read -r env_key; do
    [ -n "$env_key" ] || continue
    quoted_unset_env_args="$quoted_unset_env_args -u $(quote_arg "$env_key")"
  done <<EOF
$(firebreak_list_scrubbable_env_keys)
EOF

  quoted_args=""
  for arg in "$@"; do
    quoted_args="$quoted_args $(quote_arg "$arg")"
  done

  cat >"$launch_script" <<EOF
set -eu
workspace=$quoted_workspace
stdout_path=$quoted_stdout
stderr_path=$quoted_stderr
trace_path=$quoted_trace
exit_code_path=$quoted_exit_code
finished_at_path=$quoted_finished_at
child_pid_path=$quoted_child_pid
instance_dir=$quoted_instance_dir
launch_mode=$quoted_launch_mode
attach_mode=$attach_mode

finish() {
  status=\$1
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "command-exit:\$status" >>"\$trace_path"
  printf '%s\n' "\$status" >"\$exit_code_path"
  date -u +%Y-%m-%dT%H:%M:%SZ >"\$finished_at_path"
}

stop_child() {
  if [ -z "\${child_pid:-}" ] && [ -r "\$child_pid_path" ]; then
    child_pid=\$(cat "\$child_pid_path" 2>/dev/null || true)
  fi
  if [ -n "\${child_pid:-}" ]; then
    kill "\$child_pid" 2>/dev/null || true
    wait "\$child_pid" 2>/dev/null || true
  fi
  finish 143
  exit 143
}

trap stop_child INT TERM

mkdir -p "\$instance_dir"
printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "launch-script-start" >>"\$trace_path"
cd "\$workspace"
if [ "\$attach_mode" != "1" ]; then
  exec 1>"\$stdout_path"
  exec 2>"\$stderr_path"
fi

set +e
if [ "\$attach_mode" = "1" ]; then
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "attach-foreground-start" >>"\$trace_path"
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "firebreak-command-start" >>"\$trace_path"
  forwarded_term=\${TERM:-}
  forwarded_columns=\${COLUMNS:-}
  forwarded_lines=\${LINES:-}
  if command -v stty >/dev/null 2>&1; then
    if [ -z "\$forwarded_columns" ] || [ -z "\$forwarded_lines" ]; then
      stty_size=\$(stty size 2>/dev/null || true)
      stty_lines=\${stty_size%% *}
      stty_columns=\${stty_size##* }
      case "\$stty_lines" in
        ''|*[!0-9]*|0) stty_lines="" ;;
      esac
      case "\$stty_columns" in
        ''|*[!0-9]*|0) stty_columns="" ;;
      esac
      if [ -z "\$forwarded_lines" ] && [ -n "\$stty_lines" ]; then
        forwarded_lines=\$stty_lines
      fi
      if [ -z "\$forwarded_columns" ] && [ -n "\$stty_columns" ]; then
        forwarded_columns=\$stty_columns
      fi
    fi
  fi
  if [ "$forwarded_arg_count" -eq 0 ]; then
    env \
      $quoted_unset_env_args \
      \${forwarded_term:+TERM="\$forwarded_term"} \
      \${forwarded_columns:+COLUMNS="\$forwarded_columns"} \
      \${forwarded_lines:+LINES="\$forwarded_lines"} \
      FIREBREAK_INSTANCE_DIR="\$instance_dir" \
      FIREBREAK_LAUNCH_MODE="\$launch_mode" \
      FIREBREAK_AGENT_SESSION_MODE_OVERRIDE="agent-attach-exec" \
      bash -c '
      child_pid_path=\$1
      shift
      printf "%s\n" "\$BASHPID" >"\$child_pid_path"
      exec "\$@"
    ' bash "\$child_pid_path" \
      $quoted_resolved_exec
  else
    env \
      $quoted_unset_env_args \
      \${forwarded_term:+TERM="\$forwarded_term"} \
      \${forwarded_columns:+COLUMNS="\$forwarded_columns"} \
      \${forwarded_lines:+LINES="\$forwarded_lines"} \
      FIREBREAK_INSTANCE_DIR="\$instance_dir" \
      FIREBREAK_LAUNCH_MODE="\$launch_mode" \
      FIREBREAK_AGENT_SESSION_MODE_OVERRIDE="agent-attach-exec" \
      bash -c '
      child_pid_path=\$1
      shift
      printf "%s\n" "\$BASHPID" >"\$child_pid_path"
      exec "\$@"
    ' bash "\$child_pid_path" \
      $quoted_resolved_exec$quoted_args
  fi
  command_status=\$?
else
  printf '%s %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "detached-background-start" >>"\$trace_path"
  env \
    $quoted_unset_env_args \
    FIREBREAK_INSTANCE_DIR="\$instance_dir" \
    FIREBREAK_LAUNCH_MODE="\$launch_mode" \
    $quoted_resolved_exec$quoted_args &
  child_pid=\$!
  printf '%s\n' "\$child_pid" >"\$child_pid_path"
  wait "\$child_pid"
  command_status=\$?
fi
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
  launch_mode=run
  max_instances=""
  flake_ref=""
  worker_limit_scope=""

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
      --launch-mode)
        launch_mode=$2
        shift 2
        ;;
      --max-instances)
        max_instances=$2
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
      worker_limit_scope="process"
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
      if [ -z "${FIREBREAK_FLAKE_REF:-}" ]; then
        echo "FIREBREAK_FLAKE_REF is required for firebreak worker backend" >&2
        exit 1
      fi
      [ -n "$package_name" ] || {
        echo "firebreak backend requires --package" >&2
        exit 1
      }
      validate_token "$package_name" "worker package name"
      case "$launch_mode" in
        run|shell) ;;
        *)
          echo "unsupported firebreak worker launch mode: $launch_mode" >&2
          exit 1
          ;;
      esac
      flake_ref=$FIREBREAK_FLAKE_REF
      worker_limit_scope="firebreak:$flake_ref"
      ;;
    *)
      echo "unsupported worker backend: $backend" >&2
      exit 1
      ;;
  esac

  if [ -n "$max_instances" ]; then
    validate_positive_integer "$max_instances" "worker max_instances"
    acquire_kind_limit_lock "$kind" "$worker_limit_scope"
    trap release_kind_limit_lock EXIT INT TERM
    active_count=$(count_active_workers_for_scope "$kind" "$worker_limit_scope")
    if [ "$active_count" -ge "$max_instances" ]; then
      echo "worker kind '$kind' reached max_instances=$max_instances" >&2
      exit 1
    fi
  fi

  mkdir -p "$state_dir/workers"
  created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  worker_suffix=$(printf '%s|%s|%s|%s\n' "$kind" "$backend" "$created_at" "$$" | sha256sum | cut -c1-12)
  worker_id=$kind-$worker_suffix
  worker_root=$(worker_root_for_id "$worker_id")
  stdout_path=$worker_root/stdout.log
  stderr_path=$worker_root/stderr.log
  trace_path=$worker_root/trace.log
  status="running"
  pid=0
  finished_at=""
  exit_code=""
  stop_requested=0
  bridge_request_dir=${FIREBREAK_WORKER_BRIDGE_REQUEST_DIR:-}
  bridge_request_trace_path=${FIREBREAK_WORKER_BRIDGE_TRACE_PATH:-}

  launch_script_tmp=$(mktemp "$state_dir/workers/.launch.XXXXXX")
  case "$backend" in
    process)
      if ! write_process_launch_script "$launch_script_tmp" "$attach_mode" "$@"; then
        rm -f "$launch_script_tmp"
        exit 1
      fi
      ;;
    firebreak)
      if ! write_firebreak_launch_script "$launch_script_tmp" "$attach_mode" "$@"; then
        rm -f "$launch_script_tmp"
        exit 1
      fi
      ;;
  esac

  mkdir -p "$worker_root"
  : >"$stdout_path"
  : >"$stderr_path"
  : >"$trace_path"
  launch_script=$worker_root/launch.sh
  mv "$launch_script_tmp" "$launch_script"

  if [ "$attach_mode" = "1" ]; then
    pid=$$
    capture_process_identity "$pid"
    pid_boot_id=$captured_process_boot_id
    pid_start_time=$captured_process_start_time
    write_metadata
    if [ -n "$bridge_request_dir" ] && [ -d "$bridge_request_dir" ]; then
      printf '%s\n' "$worker_id" >"$bridge_request_dir/worker-id" || true
    fi
    release_kind_limit_lock
    trap - EXIT INT TERM
    configure_attach_tty
    trap restore_attach_tty EXIT INT TERM
    set +e
    bash "$launch_script"
    attach_status=$?
    set -e
    restore_attach_tty
    exit "$attach_status"
  fi

  nohup bash "$launch_script" >/dev/null 2>&1 </dev/null &
  pid=$!
  disown "$pid" 2>/dev/null || true
  capture_process_identity "$pid"
  pid_boot_id=$captured_process_boot_id
  pid_start_time=$captured_process_start_time
  write_metadata
  if [ -n "$bridge_request_dir" ] && [ -d "$bridge_request_dir" ]; then
    printf '%s\n' "$worker_id" >"$bridge_request_dir/worker-id" || true
  fi
  release_kind_limit_lock
  trap - EXIT INT TERM

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

print_ps_table() {
  json_input=$1
  JSON_INPUT=$json_input python3 - <<'PY'
import json
import os

items = json.loads(os.environ["JSON_INPUT"])
print(f"{'WORKER ID':<22} {'KIND':<14} {'BACKEND':<10} {'STATUS':<10} {'EXIT':<6}")
for item in items:
    exit_code = item.get("exit_code")
    print(
        f"{item.get('worker_id', ''):<22} "
        f"{item.get('kind', ''):<14} "
        f"{item.get('backend', ''):<10} "
        f"{item.get('status', ''):<10} "
        f"{('-' if exit_code is None else exit_code)!s:<6}"
    )
PY
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
  refresh_worker_status "$1" 0
  emit_metadata_json
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
  if process_is_alive "$pid" "$pid_boot_id" "$pid_start_time"; then
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

force_kill_worker() {
  target_worker_id=$1
  refresh_worker_status "$target_worker_id"
  load_worker "$target_worker_id"

  stop_requested=1
  if process_is_alive "$pid" "$pid_boot_id" "$pid_start_time"; then
    status="stopping"
    write_metadata

    if [ -f "$worker_root/child-pid" ]; then
      child_pid=$(cat "$worker_root/child-pid")
      kill -KILL "$child_pid" 2>/dev/null || true
    fi
    kill -KILL "$pid" 2>/dev/null || true
  else
    refresh_worker_status "$target_worker_id"
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

debug_requests_json() {
  bridge_debug_dir=${FIREBREAK_WORKER_BRIDGE_DIR:-}
  if [ -z "$bridge_debug_dir" ] || ! [ -d "$bridge_debug_dir/requests" ]; then
    printf '%s\n' '[]'
    return 0
  fi

  first=1
  printf '[\n'
  for request_dir in "$bridge_debug_dir"/requests/*; do
    [ -d "$request_dir" ] || continue
    request_id=$(basename "$request_dir")
    request_payload=""
    request_trace=""
    request_exit_code=""
    has_response=false

    if [ -f "$request_dir/request.json" ]; then
      request_payload=$(cat "$request_dir/request.json")
    fi
    if [ -f "$request_dir/trace.log" ]; then
      request_trace=$(tail -n 20 "$request_dir/trace.log")
    fi
    if [ -f "$request_dir/response.exit-code" ]; then
      request_exit_code=$(cat "$request_dir/response.exit-code")
      has_response=true
    fi

    if [ "$first" = "1" ]; then
      first=0
    else
      printf ',\n'
    fi

    cat <<EOF
{
  "request_id": "$(json_escape "$request_id")",
  "request_json": $(if [ -n "$request_payload" ]; then printf '"%s"' "$(json_escape "$request_payload")"; else printf 'null'; fi),
  "trace_tail": $(if [ -n "$request_trace" ]; then printf '"%s"' "$(json_escape "$request_trace")"; else printf 'null'; fi),
  "response_exit_code": $(if [ -n "$request_exit_code" ]; then printf '"%s"' "$(json_escape "$request_exit_code")"; else printf 'null'; fi),
  "has_response": $has_response
}
EOF
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
      force_kill_worker "$target_worker_id"
      if ! wait_until_worker_stops "$target_worker_id"; then
        echo "timed out waiting for worker to stop before removal: $target_worker_id" >&2
        exit 1
      fi
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

debug_read_workers_json() {
  FIREBREAK_WORKERS_DIR=$state_dir/workers python3 - <<'PY'
import json
import os
import re
from pathlib import Path
from typing import Optional

workers_dir = Path(os.environ["FIREBREAK_WORKERS_DIR"])
items = []

ANSI_TRANSCRIPT_ESCAPE_RE = re.compile(
    r"\x1B(?:"
    r"\[[0-?]*[ -/]*[@-~]"
    r"|\][^\x1b\x07]*(?:\x07|\x1b\\)"
    r"|P.*?\x1b\\"
    r"|[@-Z\\-_]"
    r")",
    re.DOTALL,
)


def read_text(path: Path) -> Optional[str]:
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8").strip()


def file_size(path_str: Optional[str]) -> Optional[int]:
    if not path_str:
        return None
    path = Path(path_str)
    if not path.exists():
        return None
    try:
        return path.stat().st_size
    except OSError:
        return None


def sanitize_display_text(text: str) -> str:
    text = ANSI_TRANSCRIPT_ESCAPE_RE.sub("", text)
    return text.replace("\r", "")


def tail_text(path: Path, line_count: int = 20) -> Optional[str]:
    if not path.is_file():
        return None
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    if not lines:
        return None
    return sanitize_display_text("\n".join(lines[-line_count:]))


def last_trace_event(trace_tail: Optional[str]) -> Optional[str]:
    if not trace_tail:
        return None
    last_line = trace_tail.splitlines()[-1].strip()
    if not last_line:
        return None
    parts = last_line.split(" ", 1)
    if len(parts) != 2:
        return last_line
    return parts[1]


def maybe_load_json(path: Path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def nested_runtime_snapshot(worker_dir: Path):
    instance_dir = worker_dir / "instance"
    metadata = maybe_load_json(instance_dir / ".firebreak-runtime.json")
    if not isinstance(metadata, dict):
        return None

    log_keys = [
        "wrapper_trace_log",
        "attach_pty_log",
        "runner_stdout_log",
        "runner_stderr_log",
        "virtiofs_hostcwd_log",
        "virtiofs_agent_config_log",
        "virtiofs_agent_exec_log",
        "virtiofs_agent_tools_log",
        "virtiofs_worker_bridge_log",
        "worker_bridge_server_log",
    ]
    log_tails = {}
    log_sizes = {}
    for key in log_keys:
        path_value = metadata.get(key)
        if not path_value:
            continue
        log_sizes[key] = file_size(path_value)
        tail = tail_text(Path(path_value), line_count=20)
        if tail:
            log_tails[key] = tail

    snapshot = dict(metadata)
    snapshot["log_tails"] = log_tails
    snapshot["log_sizes"] = log_sizes

    agent_exec_output_dir = metadata.get("agent_exec_output_dir")
    if agent_exec_output_dir:
        agent_exec_dir = Path(agent_exec_output_dir)
        agent_exec = {}
        for name in ["attach_stage", "exit_code", "stdout", "stderr", "command-processes.txt", "command-tty.txt", "interactive-echo.log"]:
            path = agent_exec_dir / name
            if path.exists():
                key_name = name.replace("-", "_").replace(".txt", "").replace(".log", "")
                agent_exec[f"{key_name}_size"] = file_size(str(path))
                text = tail_text(path, line_count=20)
                if text:
                    agent_exec[f"{key_name}_tail"] = text
        for name in ["bootstrap-state.json", "command-state.json"]:
            path = agent_exec_dir / name
            value = maybe_load_json(path)
            if value is not None:
                agent_exec[name.replace("-", "_").replace(".json", "")] = value
        if agent_exec:
            snapshot["agent_exec_output"] = agent_exec
    return snapshot


def bridge_request_snapshot(
    request_dir_str: Optional[str],
    trace_path_str: Optional[str],
    worker_root: Optional[Path] = None,
):
    request_dir = Path(request_dir_str) if request_dir_str else None
    request_path = (request_dir / "request.json") if request_dir is not None else None
    persisted_trace_path = (worker_root / "bridge-request-trace.log") if worker_root else None
    persisted_response_exit_path = (worker_root / "bridge-request-response-exit-code") if worker_root else None

    request_id = request_dir.name if request_dir is not None else None
    trace_path = None
    if request_dir is not None and request_dir.is_dir():
        candidate_trace = Path(trace_path_str) if trace_path_str else request_dir / "trace.log"
        if candidate_trace.exists():
            trace_path = candidate_trace
    if trace_path is None and persisted_trace_path is not None and persisted_trace_path.exists():
        trace_path = persisted_trace_path

    if request_dir is None and trace_path is None and not (
        persisted_response_exit_path is not None and persisted_response_exit_path.exists()
    ):
        return None

    snapshot = {
        "request_dir": str(request_dir) if request_dir is not None else None,
        "request_id": request_id,
        "trace_path": str(trace_path) if trace_path is not None else None,
        "trace_size": file_size(str(trace_path)) if trace_path is not None else None,
    }
    request_payload = maybe_load_json(request_path) if request_path is not None and request_path.exists() else None
    if isinstance(request_payload, dict):
        snapshot["term"] = request_payload.get("term")
        snapshot["columns"] = request_payload.get("columns")
        snapshot["lines"] = request_payload.get("lines")
        snapshot["interactive"] = request_payload.get("interactive")
        snapshot["attach"] = request_payload.get("attach")
    if trace_path is not None:
        try:
            trace_text = trace_path.read_text(encoding="utf-8")
        except Exception:
            trace_text = ""
        trace_tail = tail_text(trace_path)
        if trace_tail:
            snapshot["trace_tail"] = trace_tail
            snapshot["last_trace_event"] = last_trace_event(trace_tail)
        if trace_text:
            for line in trace_text.splitlines():
                if line.startswith("attach-term-effective:"):
                    snapshot["effective_term"] = line.split(":", 1)[1]
                elif line.startswith("attach-size:"):
                    snapshot["effective_size"] = line.split(":", 1)[1]
        if persisted_trace_path is not None and trace_path == persisted_trace_path:
            snapshot["trace_persisted"] = True
    response_exit_code = None
    if request_dir is not None and request_dir.is_dir():
        response_exit_code = read_text(request_dir / "response.exit-code")
    if not response_exit_code and persisted_response_exit_path is not None:
        response_exit_code = read_text(persisted_response_exit_path)
    if response_exit_code:
        snapshot["response_exit_code"] = response_exit_code
    return snapshot


def pid_alive(pid: Optional[int]) -> Optional[bool]:
    if pid is None:
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    stat_path = Path("/proc") / str(pid) / "stat"
    if stat_path.is_file():
        try:
            process_state = stat_path.read_text(encoding="utf-8").split()[2]
        except Exception:
            return True
        return process_state != "Z"
    return True


def process_info(pid: int):
    proc_dir = Path("/proc") / str(pid)
    if not proc_dir.is_dir():
        return None
    cmdline = ""
    cmdline_path = proc_dir / "cmdline"
    if cmdline_path.is_file():
        raw = cmdline_path.read_bytes().replace(b"\x00", b" ").strip()
        cmdline = raw.decode("utf-8", errors="replace")
    state = None
    tty_nr = None
    stat_path = proc_dir / "stat"
    if stat_path.is_file():
        try:
            parts = stat_path.read_text(encoding="utf-8").split()
            if len(parts) > 6:
                state = parts[2]
                tty_nr = parts[6]
        except Exception:
            pass
    return {
        "pid": pid,
        "alive": pid_alive(pid),
        "state": state,
        "tty_nr": tty_nr,
        "cmdline": cmdline,
    }


def process_children(pid: int):
    children_path = Path("/proc") / str(pid) / "task" / str(pid) / "children"
    if not children_path.is_file():
        return []
    try:
        data = children_path.read_text(encoding="utf-8").strip()
    except Exception:
        return []
    if not data:
        return []
    result = []
    for token in data.split():
        if token.isdigit():
            result.append(int(token))
    return result


def process_tree(pid: Optional[int], depth: int = 0, max_depth: int = 3):
    if pid is None or depth > max_depth:
        return []
    info = process_info(pid)
    if info is None:
        return []
    rows = [dict(info, depth=depth)]
    for child_pid in process_children(pid):
        rows.extend(process_tree(child_pid, depth + 1, max_depth))
    return rows

if workers_dir.is_dir():
    for worker_dir in sorted(workers_dir.iterdir()):
        metadata_path = worker_dir / "metadata.json"
        if metadata_path.is_file():
            try:
                item = json.loads(metadata_path.read_text(encoding="utf-8"))
                trace_path = Path(item.get("trace_path") or worker_dir / "trace.log")
                trace_tail = tail_text(trace_path)
                child_pid_raw = read_text(worker_dir / "child-pid")
                child_pid = int(child_pid_raw) if child_pid_raw and child_pid_raw.isdigit() else None
                pid_is_alive = pid_alive(item.get("pid"))
                item["stdout_size"] = file_size(item.get("stdout_path"))
                item["stderr_size"] = file_size(item.get("stderr_path"))
                item["trace_size"] = file_size(str(trace_path))
                item["trace_tail"] = trace_tail
                item["last_trace_event"] = last_trace_event(trace_tail)
                item["bridge_request_dir"] = item.get("bridge_request_dir")
                item["bridge_request_trace_path"] = item.get("bridge_request_trace_path")
                item["pid_alive"] = pid_is_alive
                item["child_pid"] = child_pid
                item["child_pid_alive"] = pid_alive(child_pid)
                item["instance_dir"] = str(worker_dir / "instance") if (worker_dir / "instance").is_dir() else None
                item["nested_runtime"] = nested_runtime_snapshot(worker_dir)
                item["bridge_request"] = bridge_request_snapshot(
                    item.get("bridge_request_dir"),
                    item.get("bridge_request_trace_path"),
                    worker_dir,
                )
                item["process_tree"] = (
                    process_tree(item.get("pid"))
                    if pid_is_alive and item.get("status") in {"active", "running", "stopping"}
                    else []
                )
                items.append(item)
                continue
            except Exception:
                pass

        items.append(
            {
                "worker_id": worker_dir.name,
                "authority": "host",
                "backend": None,
                "kind": None,
                "status": "unknown",
                "workspace": None,
                "package_name": None,
                "launch_mode": None,
                "pid": None,
                "stdout_path": None,
                "stderr_path": None,
                "trace_path": str(worker_dir / "trace.log"),
                "worker_root": str(worker_dir),
                "created_at": None,
                "finished_at": None,
                "exit_code": None,
                "stop_requested": False,
                "stdout_size": None,
                "stderr_size": None,
                "trace_size": None,
                "trace_tail": tail_text(worker_dir / "trace.log"),
                "last_trace_event": last_trace_event(tail_text(worker_dir / "trace.log")),
                "bridge_request_dir": read_text(worker_dir / "bridge-request-dir"),
                "bridge_request_trace_path": read_text(worker_dir / "bridge-request-trace-path"),
                "pid_alive": None,
                "child_pid": None,
                "child_pid_alive": None,
                "instance_dir": str(worker_dir / "instance") if (worker_dir / "instance").is_dir() else None,
                "nested_runtime": nested_runtime_snapshot(worker_dir),
                "bridge_request": bridge_request_snapshot(
                    read_text(worker_dir / "bridge-request-dir"),
                    read_text(worker_dir / "bridge-request-trace-path"),
                    worker_dir,
                ),
                "process_tree": [],
            }
        )

print(json.dumps(items))
PY
}

debug_worker() {
  debug_json=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        debug_json=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done

  mkdir -p "$state_dir/workers"
  for_each_worker :
  workers_json=$(debug_read_workers_json)
  worker_count=$(JSON_INPUT=$workers_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["JSON_INPUT"])
print(len(items))
PY
)
  active_worker_count=$(JSON_INPUT=$workers_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["JSON_INPUT"])
count = 0
for item in items:
    if item.get("status") in {"active", "running", "stopping"}:
        count += 1
print(count)
PY
)

  bridge_dir=${FIREBREAK_WORKER_BRIDGE_DIR:-}
  requests_json='[]'
  request_count=0
  if [ -n "$bridge_dir" ] && [ -d "$bridge_dir/requests" ]; then
    requests_json=$(debug_requests_json "$bridge_dir/requests")
    request_count=$(JSON_INPUT=$requests_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["JSON_INPUT"])
print(len(items))
PY
)
  fi

  if [ "$debug_json" = "1" ]; then
    cat <<EOF
{
  "authority": "host",
  "state_dir": "$(json_escape "$state_dir")",
  "worker_count": $worker_count,
  "active_worker_count": $active_worker_count,
  "bridge_dir": $([ -n "$bridge_dir" ] && printf '"%s"' "$(json_escape "$bridge_dir")" || printf 'null'),
  "request_count": $request_count,
  "workers": $workers_json,
  "requests": $requests_json
}
EOF
    exit 0
  fi

  printf '%s\n' 'Firebreak worker broker'
  printf 'state_dir: %s\n' "$state_dir"
  if [ -n "$bridge_dir" ]; then
    printf 'bridge_dir: %s\n' "$bridge_dir"
  fi
  printf 'worker_count: %s\n' "$worker_count"
  printf 'active_worker_count: %s\n' "$active_worker_count"
  if [ "$worker_count" -gt 0 ]; then
    printf '\n%s\n' 'Workers'
    print_ps_table "$workers_json"
    printf '\n%s\n' 'Worker details'
    WORKERS_JSON=$workers_json python3 - <<'PY'
import json
import os

for item in json.loads(os.environ["WORKERS_JSON"]):
    print(f"- {item.get('worker_id')}")
    print(f"  status: {item.get('status')}")
    print(f"  backend: {item.get('backend')}")
    print(f"  pid: {item.get('pid')} alive={item.get('pid_alive')}")
    child_pid = item.get("child_pid")
    if child_pid is not None:
        print(f"  child_pid: {child_pid} alive={item.get('child_pid_alive')}")
    print(f"  stdout_size: {item.get('stdout_size')}")
    print(f"  stderr_size: {item.get('stderr_size')}")
    print(f"  trace_size: {item.get('trace_size')}")
    last_trace_event = item.get("last_trace_event")
    if last_trace_event:
        print(f"  last_trace_event: {last_trace_event}")
    instance_dir = item.get("instance_dir")
    if instance_dir:
        print(f"  instance_dir: {instance_dir}")
    nested_runtime = item.get("nested_runtime")
    if isinstance(nested_runtime, dict):
        runtime_dir = nested_runtime.get("host_runtime_dir")
        if runtime_dir:
            print(f"  nested_runtime_dir: {runtime_dir}")
        session_mode = nested_runtime.get("session_mode")
        if session_mode:
            print(f"  nested_session_mode: {session_mode}")
        log_sizes = nested_runtime.get("log_sizes") or {}
        for key, size in log_sizes.items():
            print(f"  {key}_size: {size}")
        log_tails = nested_runtime.get("log_tails") or {}
        for key, tail in log_tails.items():
            print(f"  {key}:")
            for line in str(tail).splitlines():
                print(f"    {line}")
        agent_exec_output = nested_runtime.get("agent_exec_output") or {}
        for key, value in agent_exec_output.items():
            if key in {"bootstrap_state", "command_state"} and isinstance(value, dict):
                phase = value.get("phase")
                status = value.get("status")
                detail = value.get("detail")
                updated_at = value.get("updated_at")
                prefix = f"guest_{key}"
                if phase:
                    print(f"  {prefix}_phase: {phase}")
                if status:
                    print(f"  {prefix}_status: {status}")
                if detail:
                    print(f"  {prefix}_detail: {detail}")
                command = value.get("command")
                if command:
                    print(f"  {prefix}_command: {command}")
                exit_code = value.get("exit_code")
                if exit_code is not None:
                    print(f"  {prefix}_exit_code: {exit_code}")
                if updated_at:
                    print(f"  {prefix}_updated_at: {updated_at}")
                continue
            if key.endswith("_tail"):
                print(f"  agent_exec_{key}:")
                for line in str(value).splitlines():
                    print(f"    {line}")
            else:
                print(f"  agent_exec_{key}: {value}")
    trace_tail = item.get("trace_tail")
    if trace_tail:
        print("  trace_tail:")
        for line in trace_tail.splitlines():
            print(f"    {line}")
    bridge_request = item.get("bridge_request")
    if isinstance(bridge_request, dict):
        request_id = bridge_request.get("request_id")
        if request_id:
            print(f"  bridge_request_id: {request_id}")
        request_term = bridge_request.get("term")
        if request_term is not None:
            print(f"  bridge_request_term: {request_term}")
        effective_term = bridge_request.get("effective_term")
        if effective_term is not None:
            print(f"  bridge_request_effective_term: {effective_term}")
        request_columns = bridge_request.get("columns")
        if request_columns is not None:
            print(f"  bridge_request_columns: {request_columns}")
        request_lines = bridge_request.get("lines")
        if request_lines is not None:
            print(f"  bridge_request_lines: {request_lines}")
        effective_size = bridge_request.get("effective_size")
        if effective_size is not None:
            print(f"  bridge_request_effective_size: {effective_size}")
        if bridge_request.get("attach") is not None:
            print(f"  bridge_request_attach: {bridge_request.get('attach')}")
        if bridge_request.get("interactive") is not None:
            print(f"  bridge_request_interactive: {bridge_request.get('interactive')}")
        trace_size = bridge_request.get("trace_size")
        if trace_size is not None:
            print(f"  bridge_request_trace_size: {trace_size}")
        last_event = bridge_request.get("last_trace_event")
        if last_event:
            print(f"  bridge_request_last_event: {last_event}")
        response_exit_code = bridge_request.get("response_exit_code")
        if response_exit_code is not None:
            print(f"  bridge_request_response_exit_code: {response_exit_code}")
        bridge_trace_tail = bridge_request.get("trace_tail")
        if bridge_trace_tail:
            print("  bridge_request_trace_tail:")
            for line in bridge_trace_tail.splitlines():
                print(f"    {line}")
    process_tree = item.get("process_tree") or []
    if process_tree:
        print("  process_tree:")
        for node in process_tree:
            indent = "    " + "  " * int(node.get("depth") or 0)
            state = node.get("state")
            cmdline = node.get("cmdline") or ""
            print(f"{indent}{node.get('pid')} state={state} alive={node.get('alive')} cmd={cmdline}")
PY
  fi
  if [ "$request_count" -gt 0 ]; then
    printf '\n%s\n' 'Requests'
    REQUESTS_JSON=$requests_json python3 - <<'PY'
import json
import os

for item in json.loads(os.environ["REQUESTS_JSON"]):
    print(f"- {item['request_id']}")
    request_json = item.get("request_json")
    if request_json:
        print(f"  request.json: {request_json}")
    trace_tail = item.get("trace_tail")
    if trace_tail:
        print("  trace_tail:")
        for line in trace_tail.splitlines():
            print(f"    {line}")
    if item.get("has_response"):
        print(f"  response_exit_code: {item.get('response_exit_code')}")
PY
  fi
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
  debug)
    shift
    debug_worker "$@"
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
