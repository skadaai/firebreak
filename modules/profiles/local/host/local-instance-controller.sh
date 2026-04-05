local_controller_mode=${FIREBREAK_LOCAL_CONTROLLER_MODE:-client}

local_controller_prepare_state() {
  local_controller_state_dir=$runner_workdir/.firebreak-local
  local_controller_pid_file=$local_controller_state_dir/daemon.pid
  local_controller_runtime_dir_file=$local_controller_state_dir/runtime-dir
  local_controller_spawn_log=$local_controller_state_dir/spawn.log
}

local_controller_runtime_dir() {
  if ! [ -r "$local_controller_runtime_dir_file" ]; then
    return 1
  fi
  cat "$local_controller_runtime_dir_file"
}

local_controller_pid_is_alive() {
  if ! [ -r "$local_controller_pid_file" ]; then
    return 1
  fi
  local_controller_pid=$(cat "$local_controller_pid_file" 2>/dev/null || true)
  case "$local_controller_pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$local_controller_pid" 2>/dev/null
}

local_controller_should_dispatch() {
  [ "$local_controller_mode" = "client" ] || return 1
  [ "$runtime_backend" = "cloud-hypervisor" ] || return 1
  [ "$agent_session_mode" = "agent-exec" ] || return 1
  [ "$instance_ephemeral" != "1" ] || return 1
}

local_controller_wait_for_ready() {
  local_controller_prepare_state
  for _ in $(seq 1 900); do
    if ! local_controller_pid_is_alive; then
      break
    fi

    controller_runtime_dir=$(local_controller_runtime_dir 2>/dev/null || true)
    if [ -n "$controller_runtime_dir" ] \
      && [ -r "$controller_runtime_dir/o/command-agent-ready" ] \
      && [ -S "$control_socket" ]; then
      return 0
    fi
    sleep 0.2
  done

  echo "warm local controller did not become ready for $runner_workdir" >&2
  if [ -s "$local_controller_spawn_log" ]; then
    cat "$local_controller_spawn_log" >&2
  fi
  exit 1
}

local_controller_ensure_running() {
  local_controller_prepare_state
  mkdir -p "$local_controller_state_dir"

  if local_controller_pid_is_alive; then
    local_controller_wait_for_ready
    return 0
  fi

  rm -f "$local_controller_pid_file" "$local_controller_runtime_dir_file"
  setsid env \
    FIREBREAK_INSTANCE_DIR="$runner_workdir" \
    FIREBREAK_AGENT_SESSION_MODE_OVERRIDE=agent-service \
    FIREBREAK_LOCAL_CONTROLLER_MODE=daemon \
    FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
    "$0" >"$local_controller_spawn_log" 2>&1 < /dev/null &
  local_controller_pid=$!
  printf '%s\n' "$local_controller_pid" > "$local_controller_pid_file"
  local_controller_wait_for_ready
}

local_controller_record_runtime_dir() {
  local_controller_prepare_state
  mkdir -p "$local_controller_state_dir"
  printf '%s\n' "$host_runtime_dir" > "$local_controller_runtime_dir_file"
  printf '%s\n' "${BASHPID:-$$}" > "$local_controller_pid_file"
}

local_controller_clear_state() {
  local_controller_prepare_state
  rm -f "$local_controller_pid_file" "$local_controller_runtime_dir_file"
}

local_controller_write_request() {
  controller_exec_output_dir=$1
  controller_request_path=$controller_exec_output_dir/request.json
  controller_request_id=$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID:-$$}

  rm -f \
    "$controller_request_path" \
    "$controller_exec_output_dir/attach_stage" \
    "$controller_exec_output_dir/exit_code" \
    "$controller_exec_output_dir/stdout" \
    "$controller_exec_output_dir/stderr" \
    "$controller_exec_output_dir/command-signals.stream" \
    "$controller_exec_output_dir/command-processes.txt" \
    "$controller_exec_output_dir/command-tty.txt"

  REQUEST_PATH=$controller_request_path \
  REQUEST_ID=$controller_request_id \
  REQUEST_SESSION_MODE=agent-exec \
  REQUEST_COMMAND=$agent_command_override \
  REQUEST_START_DIR=$host_cwd \
  REQUEST_TERM=$agent_term \
  REQUEST_COLUMNS=$agent_columns \
  REQUEST_LINES=$agent_lines \
  python3 - <<'PY'
import json
import os

payload = {
    "request_id": os.environ["REQUEST_ID"],
    "session_mode": os.environ["REQUEST_SESSION_MODE"],
    "command": os.environ["REQUEST_COMMAND"],
    "start_dir": os.environ["REQUEST_START_DIR"],
    "term": os.environ["REQUEST_TERM"],
    "columns": os.environ["REQUEST_COLUMNS"],
    "lines": os.environ["REQUEST_LINES"],
}

with open(os.environ["REQUEST_PATH"], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

local_controller_wait_for_response() {
  controller_exec_output_dir=$1
  controller_command_state_path=$controller_exec_output_dir/command-state.json
  controller_exit_code_path=$controller_exec_output_dir/exit_code

  for _ in $(seq 1 7200); do
    if ! local_controller_pid_is_alive; then
      echo "warm local controller exited before command completion for $runner_workdir" >&2
      if [ -s "$local_controller_spawn_log" ]; then
        cat "$local_controller_spawn_log" >&2
      fi
      exit 1
    fi

    if [ -f "$controller_exit_code_path" ] \
      && [ -f "$controller_command_state_path" ] \
      && grep -F -q "\"request_id\": \"$controller_request_id\"" "$controller_command_state_path"; then
      return 0
    fi
    sleep 0.1
  done

  echo "warm local controller timed out waiting for command response for $runner_workdir" >&2
  exit 1
}

local_controller_dispatch_request() {
  local_controller_prepare_state
  local_controller_ensure_running

  controller_runtime_dir=$(local_controller_runtime_dir)
  controller_exec_output_dir=$controller_runtime_dir/o
  if ! [ -d "$controller_exec_output_dir" ]; then
    echo "warm local controller exec output directory is unavailable: $controller_exec_output_dir" >&2
    exit 1
  fi

  local_controller_write_request "$controller_exec_output_dir"
  local_controller_wait_for_response "$controller_exec_output_dir"

  if [ -f "$controller_exec_output_dir/stdout" ]; then
    cat "$controller_exec_output_dir/stdout"
  fi
  if [ -f "$controller_exec_output_dir/stderr" ]; then
    cat "$controller_exec_output_dir/stderr" >&2
  fi

  if ! [ -f "$controller_exec_output_dir/exit_code" ]; then
    echo "warm local controller did not produce an exit code for $runner_workdir" >&2
    exit 1
  fi

  command_status=$(cat "$controller_exec_output_dir/exit_code" 2>/dev/null || true)
  case "$command_status" in
    ''|*[!0-9]*)
      echo "warm local controller produced an invalid exit code: $command_status" >&2
      exit 1
      ;;
  esac

  exit "$command_status"
}
