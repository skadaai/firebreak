set -eu

@FIREBREAK_PROJECT_CONFIG_LIB@
@FIREBREAK_CLOUD_HYPERVISOR_NETWORK_LIB@

host_cwd=$PWD
host_uid=$(id -u)
host_gid=$(id -g)
firebreak_load_project_config
resolved_firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
firebreak_state_root=${FIREBREAK_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}/firebreak}
default_firebreak_state_root=${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}/firebreak
worker_state_dir=${FIREBREAK_WORKER_STATE_DIR:-$firebreak_state_root/worker-broker}
specific_state_mode_var=@AGENT_ENV_PREFIX@_STATE_MODE
specific_state_mode=${!specific_state_mode_var:-}
state_mode=${specific_state_mode:-${FIREBREAK_STATE_MODE:-host}}
requested_launch_mode=${FIREBREAK_LAUNCH_MODE:-run}
requested_worker_mode=${FIREBREAK_WORKER_MODE:-}
requested_worker_modes=${FIREBREAK_WORKER_MODES:-}
agent_session_mode_override=${FIREBREAK_AGENT_SESSION_MODE_OVERRIDE:-}
agent_session_mode=agent
default_agent_command=@DEFAULT_AGENT_COMMAND@
runtime_backend=@RUNTIME_BACKEND@
agent_command_override=""
shell_command_override=${AGENT_VM_COMMAND:-}
shared_state_root_host_dir=""
shared_credential_slots_host_dir=""
workspace_bootstrap_config_host_dir=@WORKSPACE_BOOTSTRAP_CONFIG_HOST_DIR@
host_config_adoption_enabled=@HOST_CONFIG_ADOPTION_ENABLED@
shared_credential_slots_enabled=@SHARED_CREDENTIAL_SLOTS_ENABLED@
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

normalize_term_name() {
  term_name=$1
  case "$term_name" in
    ansi|dumb|vt100|vt102|vt220)
      printf '%s\n' "xterm-256color"
      ;;
    *)
      printf '%s\n' "$term_name"
      ;;
  esac
}

sanitize_positive_dimension() {
  dimension=$1
  case "$dimension" in
    ''|*[!0-9]*|0)
      printf '%s\n' ""
      ;;
    *)
      printf '%s\n' "$dimension"
      ;;
  esac
}

reject_comma_path() {
  path=$1
  description=$2
  case "$path" in
    *,*)
      echo "$description contains a comma, which the Apple Silicon vfkit runtime share injection does not support: $path" >&2
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

require_absolute_host_path() {
  path=$1
  description=$2

  case "$path" in
    /*) ;;
    *)
      echo "$description must resolve to an absolute host path: $path" >&2
      exit 1
      ;;
  esac
}

ensure_host_state_subdir() {
  host_root=$1
  state_subdir=$2
  bootstrap_target=$3
  host_state_path=$host_root/$state_subdir

  mkdir -p "$host_root"

  materialize_host_state_target() {
    source_path=$1
    destination_path=$2

    rm -rf "$destination_path"
    mkdir -p "$destination_path"
    if [ -d "$source_path" ]; then
      cp -a "$source_path"/. "$destination_path"/
    elif [ -e "$source_path" ] || [ -L "$source_path" ]; then
      cp -a "$source_path" "$destination_path"/
    fi
  }

  path_within_root() {
    candidate_path=$1
    root_path=$2

    case "$candidate_path" in
      "$root_path"|"$root_path"/*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  maybe_materialize_external_state() {
    current_path=$1
    root_path=$2

    if ! [ -L "$current_path" ]; then
      return 0
    fi

    resolved_link=$(readlink -f "$current_path" 2>/dev/null || true)
    resolved_root=$(readlink -f "$root_path" 2>/dev/null || true)
    if [ -z "$resolved_link" ] || [ -z "$resolved_root" ]; then
      return 0
    fi

    if path_within_root "$resolved_link" "$resolved_root"; then
      return 0
    fi

    rm -f "$current_path"
    materialize_host_state_target "$resolved_link" "$current_path"
    printf '%s\n' "firebreak: materialized external tool state into $current_path from $resolved_link" >&2
  }

  if [ -n "$bootstrap_target" ] && ! [ -e "$host_state_path" ] && ! [ -L "$host_state_path" ] && { [ -e "$bootstrap_target" ] || [ -L "$bootstrap_target" ]; }; then
    reject_whitespace_path "$bootstrap_target" "host state bootstrap target"
    resolved_target=$(readlink -f "$bootstrap_target" 2>/dev/null || true)
    resolved_root=$(readlink -f "$host_root" 2>/dev/null || true)
    if [ -n "$resolved_target" ] && [ -n "$resolved_root" ] && path_within_root "$resolved_target" "$resolved_root"; then
      ln -s "$bootstrap_target" "$host_state_path"
      printf '%s\n' "firebreak: adopted existing tool state as $host_state_path -> $bootstrap_target" >&2
    else
      materialize_host_state_target "$bootstrap_target" "$host_state_path"
      printf '%s\n' "firebreak: materialized adopted tool state into $host_state_path from $bootstrap_target" >&2
    fi
    return 0
  fi

  maybe_materialize_external_state "$host_state_path" "$host_root"

  if ! [ -e "$host_state_path" ] && ! [ -L "$host_state_path" ]; then
    mkdir -p "$host_state_path"
  fi
}

append_optional_env_default() {
  key=$1
  value=$2
  [ -n "$value" ] || return 0

  printf -v quoted_value '%q' "$value"
  printf ": \"\${%s:=%s}\"\n" "$key" "$quoted_value" >> "$shared_state_root_env_file"
  printf 'export %s\n' "$key" >> "$shared_state_root_env_file"
}

append_matching_env_defaults() {
  suffix_pattern=$1

  while IFS= read -r env_entry; do
    env_key=${env_entry%%=*}
    env_value=${env_entry#*=}
    case "$env_key" in
      *"$suffix_pattern")
        append_optional_env_default "$env_key" "$env_value"
        ;;
    esac
  done <<EOF
$(env)
EOF
}

default_state_root=$(resolve_host_dir "${FIREBREAK_STATE_ROOT:-@DEFAULT_STATE_ROOT@}")
default_credential_slots_host_dir=$(resolve_host_dir "${FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH:-@DEFAULT_CREDENTIAL_SLOTS_HOST_DIR@}")
workspace_bootstrap_target=""
if [ -n "$workspace_bootstrap_config_host_dir" ]; then
  workspace_bootstrap_target=$(resolve_host_dir "$workspace_bootstrap_config_host_dir")
fi
require_absolute_host_path "$default_state_root" "FIREBREAK_STATE_ROOT"
if [ -n "$workspace_bootstrap_target" ]; then
  require_absolute_host_path "$workspace_bootstrap_target" "workspace bootstrap target"
fi
shared_state_root_host_dir=$default_state_root
shared_credential_slots_host_dir=$default_credential_slots_host_dir
if [ "$shared_credential_slots_enabled" != "1" ]; then
  shared_credential_slots_host_dir=""
else
  require_absolute_host_path "$default_credential_slots_host_dir" "FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH"
fi

reject_whitespace_path "$host_cwd" "current working directory"
reject_whitespace_path "$resolved_firebreak_tmp_root" "Firebreak temporary runtime directory"
reject_whitespace_path "$firebreak_state_root" "Firebreak state root"
reject_whitespace_path "$default_firebreak_state_root" "default Firebreak state root"
reject_whitespace_path "$worker_state_dir" "Firebreak worker state directory"
if [ "$runtime_backend" = "vfkit" ]; then
  reject_comma_path "$host_cwd" "current working directory"
  reject_comma_path "$resolved_firebreak_tmp_root" "Firebreak temporary runtime directory"
fi
firebreak_tmp_root=$resolved_firebreak_tmp_root
mkdir -p "$firebreak_tmp_root"
host_runtime_dir=$(mktemp -d "$firebreak_tmp_root/r.XXXXXX")
host_runtime_share_dir=$host_runtime_dir/runtime
host_meta_dir=$host_runtime_share_dir/meta
host_exec_output_dir=$host_runtime_share_dir/exec-output
command_request_path=$host_exec_output_dir/request.json
host_agent_tools_dir=$firebreak_state_root/tools/${default_control_socket%.socket}
default_host_agent_tools_dir=$default_firebreak_state_root/tools/${default_control_socket%.socket}
host_instance_dir=$host_runtime_dir/instance
runner_stdout_log=$host_runtime_dir/runner.out
runner_stderr_log=$host_runtime_dir/runner.err
virtiofsd_hostcwd_log=$host_runtime_dir/v-cwd.log
virtiofsd_ro_store_log=$host_runtime_dir/v-ro-store.log
virtiofsd_hostruntime_log=$host_runtime_dir/v-runtime.log
virtiofsd_shared_state_root_log=$host_runtime_dir/v-shared-cfg.log
virtiofsd_shared_credential_slots_log=$host_runtime_dir/v-credential-slots.log
virtiofsd_agent_tools_log=$host_runtime_dir/v-tools.log
hostcwd_socket=$host_runtime_dir/cwd.sock
ro_store_socket=$host_runtime_dir/ro-store.sock
hostruntime_socket=$host_runtime_dir/runtime.sock
shared_state_root_socket=$host_runtime_dir/shared-cfg.sock
shared_credential_slots_socket=$host_runtime_dir/credential-slots.sock
agent_tools_socket=$host_runtime_dir/tools.sock
worker_bridge_dir=$host_runtime_share_dir/worker-bridge
worker_bridge_server_log=$host_runtime_dir/worker-bridge.log
worker_bridge_server_script=$host_runtime_dir/firebreak-worker-bridge-host.sh
worker_helper_script=$host_runtime_dir/firebreak-worker.sh
worker_bridge_enabled=@WORKER_BRIDGE_ENABLED@
wrapper_trace_log=$host_runtime_dir/wrapper-trace.log
attach_pty_log=$host_runtime_dir/attach-pty.log
agent_term=$(normalize_term_name "${TERM:-}")
agent_columns=$(sanitize_positive_dimension "${COLUMNS:-}")
agent_lines=$(sanitize_positive_dimension "${LINES:-}")

if { [ -z "$agent_columns" ] || [ -z "$agent_lines" ]; } && command -v stty >/dev/null 2>&1; then
  stty_size=$(stty size 2>/dev/null || true)
  stty_lines=${stty_size%% *}
  stty_columns=${stty_size##* }
  stty_lines=$(sanitize_positive_dimension "$stty_lines")
  stty_columns=$(sanitize_positive_dimension "$stty_columns")
  if [ -z "$agent_lines" ] && [ -n "$stty_lines" ]; then
    agent_lines=$stty_lines
  fi
  if [ -z "$agent_columns" ] && [ -n "$stty_columns" ]; then
    agent_columns=$stty_columns
  fi
fi

trace_wrapper() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >>"$wrapper_trace_log"
}

require_absolute_host_path "$shared_state_root_host_dir" "FIREBREAK_STATE_ROOT"
reject_whitespace_path "$shared_state_root_host_dir" "Firebreak host state root"
mkdir -p "$shared_state_root_host_dir"
if [ -n "$shared_credential_slots_host_dir" ]; then
  require_absolute_host_path "$shared_credential_slots_host_dir" "FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH"
  reject_whitespace_path "$shared_credential_slots_host_dir" "Firebreak credential slot root"
  mkdir -p "$shared_credential_slots_host_dir"
fi

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
cloud_hypervisor_tap_interface=""
cloud_hypervisor_host_ipv4=""
cloud_hypervisor_guest_ipv4=""
cloud_hypervisor_subnet_cidr=""
cloud_hypervisor_outbound_interface=""

case "$requested_launch_mode" in
  run)
    agent_session_mode=agent
    ;;
  shell)
    agent_session_mode=shell
    ;;
  *)
    echo "unsupported FIREBREAK_LAUNCH_MODE: $requested_launch_mode" >&2
    echo "supported values: run, shell" >&2
    exit 1
    ;;
esac

normalize_worker_mode() {
  mode_name=$1
  case "$mode_name" in
    worker)
      printf '%s\n' "vm"
      ;;
    *)
      printf '%s\n' "$mode_name"
      ;;
  esac
}

requested_worker_mode=$(normalize_worker_mode "$requested_worker_mode")

case "$requested_worker_mode" in
  ""|vm|local)
    ;;
  *)
    echo "unsupported FIREBREAK_WORKER_MODE: $requested_worker_mode" >&2
    echo "supported values: vm, local" >&2
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

case "$state_mode" in
  host|workspace|vm|fresh)
    ;;
  *)
    echo "unsupported state mode: $state_mode" >&2
    echo "supported state modes: host, workspace, vm, fresh" >&2
    exit 1
    ;;
esac

if [ "$host_config_adoption_enabled" = "1" ] && [ "$state_mode" = "host" ]; then
  ensure_host_state_subdir "$shared_state_root_host_dir" "@STATE_SUBDIR@" "$workspace_bootstrap_target"
fi

# shellcheck disable=SC2329
cleanup() {
  cloud_hypervisor_cleanup_local_network
  if [ -n "${ro_store_virtiofsd_pid:-}" ]; then
    kill "$ro_store_virtiofsd_pid" 2>/dev/null || true
    wait "$ro_store_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${hostcwd_virtiofsd_pid:-}" ]; then
    kill "$hostcwd_virtiofsd_pid" 2>/dev/null || true
    wait "$hostcwd_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${hostruntime_virtiofsd_pid:-}" ]; then
    kill "$hostruntime_virtiofsd_pid" 2>/dev/null || true
    wait "$hostruntime_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${shared_state_root_virtiofsd_pid:-}" ]; then
    kill "$shared_state_root_virtiofsd_pid" 2>/dev/null || true
    wait "$shared_state_root_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${shared_credential_slots_virtiofsd_pid:-}" ]; then
    kill "$shared_credential_slots_virtiofsd_pid" 2>/dev/null || true
    wait "$shared_credential_slots_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${agent_tools_virtiofsd_pid:-}" ]; then
    kill "$agent_tools_virtiofsd_pid" 2>/dev/null || true
    wait "$agent_tools_virtiofsd_pid" 2>/dev/null || true
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
mkdir -p "$host_agent_tools_dir"
mkdir -p "$worker_bridge_dir/requests"
if [ "$host_agent_tools_dir" != "$default_host_agent_tools_dir" ] \
  && ! [ -e "$host_agent_tools_dir/bootstrap-ready" ] \
  && [ -e "$default_host_agent_tools_dir/bootstrap-ready" ]; then
  mkdir -p "$host_agent_tools_dir"
  cp -a "$default_host_agent_tools_dir"/. "$host_agent_tools_dir"/
  trace_wrapper "agent-tools-seeded"
fi
rm -f "$control_socket"
shared_state_root_env_file=$host_meta_dir/firebreak-shared-state.env
: >"$wrapper_trace_log"
: >"$attach_pty_log"

cat >"$runtime_debug_file" <<EOF
{
  "host_runtime_dir": "$(printf '%s' "$host_runtime_dir" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "runner_workdir": "$(printf '%s' "$runner_workdir" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "session_mode": "$(printf '%s' "$agent_session_mode" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "control_socket": "$(printf '%s' "$control_socket" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "agent_exec_output_dir": "$(printf '%s' "$host_exec_output_dir" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "wrapper_trace_log": "$(printf '%s' "$wrapper_trace_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "attach_pty_log": "$(printf '%s' "$attach_pty_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "runner_stdout_log": "$(printf '%s' "$runner_stdout_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "runner_stderr_log": "$(printf '%s' "$runner_stderr_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_hostcwd_log": "$(printf '%s' "$virtiofsd_hostcwd_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_hostruntime_log": "$(printf '%s' "$virtiofsd_hostruntime_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_hostmeta_log": "$(printf '%s' "$virtiofsd_hostruntime_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_agent_config_log": "$(printf '%s' "$virtiofsd_hostruntime_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_shared_state_root_log": "$(printf '%s' "$virtiofsd_shared_state_root_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_shared_credential_slots_log": "$(printf '%s' "$virtiofsd_shared_credential_slots_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_agent_exec_log": "$(printf '%s' "$virtiofsd_hostruntime_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_agent_tools_log": "$(printf '%s' "$virtiofsd_agent_tools_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "virtiofs_worker_bridge_log": "$(printf '%s' "$virtiofsd_hostruntime_log" | sed 's/\\/\\\\/g; s/"/\\"/g')",
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

spawn_virtiofsd() {
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
}

wait_for_virtiofsd_socket() {
  socket_path=$1
  log_path=$2
  virtiofsd_pid=$3
  for _ in $(seq 1 50); do
    if [ -S "$socket_path" ]; then
      return 0
    fi
    sleep 0.1
  done

  kill "$virtiofsd_pid" 2>/dev/null || true
  wait "$virtiofsd_pid" 2>/dev/null || true
  echo "virtiofsd did not create socket: $socket_path" >&2
  if [ -s "$log_path" ]; then
    cat "$log_path" >&2
  fi
  exit 1
}

start_worker_bridge_server() {
  env \
    FIREBREAK_FLAKE_REF='@FIREBREAK_FLAKE_REF@' \
    FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG='1' \
    FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes' \
    FIREBREAK_WORKER_BRIDGE_DIR="$worker_bridge_dir" \
    FIREBREAK_WORKER_STATE_DIR="$worker_state_dir" \
    bash "$worker_bridge_server_script" "$worker_bridge_dir" "$worker_helper_script" >"$worker_bridge_server_log" 2>&1 &
  worker_bridge_server_pid=$!
  trace_wrapper "worker-bridge-ready"
}

write_command_request() {
  request_id=$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID:-$$}
  rm -f \
    "$command_request_path" \
    "$host_exec_output_dir/attach_stage" \
    "$host_exec_output_dir/exit_code" \
    "$host_exec_output_dir/stdout" \
    "$host_exec_output_dir/stderr" \
    "$host_exec_output_dir/command-signals.stream" \
    "$host_exec_output_dir/command-processes.txt" \
    "$host_exec_output_dir/command-tty.txt"
  REQUEST_PATH=$command_request_path \
  REQUEST_ID=$request_id \
  REQUEST_SESSION_MODE=$agent_session_mode \
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
  trace_wrapper "command-request-ready:$request_id"
}

printf '%s\n' "$host_cwd" > "$host_meta_dir/mount-path"
printf '%s\n' "$host_uid" > "$host_meta_dir/host-uid"
printf '%s\n' "$host_gid" > "$host_meta_dir/host-gid"
printf '%s\n' "$agent_session_mode" > "$host_meta_dir/worker-session-mode"
: > "$shared_state_root_env_file"
append_optional_env_default "FIREBREAK_STATE_MODE" "${FIREBREAK_STATE_MODE:-}"
append_optional_env_default "FIREBREAK_STATE_ROOT" "${FIREBREAK_STATE_ROOT:-}"
append_matching_env_defaults "_STATE_MODE"
append_optional_env_default "FIREBREAK_CREDENTIAL_SLOT" "${FIREBREAK_CREDENTIAL_SLOT:-}"
append_optional_env_default "FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH" "${FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH:-}"
append_matching_env_defaults "_CREDENTIAL_SLOT"
printf '%s\n' "$requested_worker_mode" > "$host_meta_dir/worker-mode"
printf '%s\n' "$requested_worker_modes" > "$host_meta_dir/worker-modes"
if [ -n "$agent_term" ]; then
  printf '%s\n' "$agent_term" > "$host_meta_dir/worker-term"
fi
if [ -n "$agent_columns" ]; then
  printf '%s\n' "$agent_columns" > "$host_meta_dir/worker-columns"
fi
if [ -n "$agent_lines" ]; then
  printf '%s\n' "$agent_lines" > "$host_meta_dir/worker-lines"
fi
if [ -n "$agent_command_override" ] && [ "$agent_session_mode" != "agent-exec" ] && [ "$agent_session_mode" != "agent-attach-exec" ]; then
  printf '%s\n' "$agent_command_override" > "$host_meta_dir/worker-command"
fi
if [ "$agent_session_mode" = "agent-exec" ] || [ "$agent_session_mode" = "agent-attach-exec" ]; then
  write_command_request
fi

cloud_hypervisor_setup_local_network

case "$runtime_backend" in
  cloud-hypervisor)
    spawn_virtiofsd "/nix/store" "$ro_store_socket" "$virtiofsd_ro_store_log"
    ro_store_virtiofsd_pid=$started_virtiofsd_pid

    spawn_virtiofsd "$host_cwd" "$hostcwd_socket" "$virtiofsd_hostcwd_log"
    hostcwd_virtiofsd_pid=$started_virtiofsd_pid

    spawn_virtiofsd "$host_runtime_share_dir" "$hostruntime_socket" "$virtiofsd_hostruntime_log"
    hostruntime_virtiofsd_pid=$started_virtiofsd_pid

    if [ -n "$shared_state_root_host_dir" ]; then
      spawn_virtiofsd "$shared_state_root_host_dir" "$shared_state_root_socket" "$virtiofsd_shared_state_root_log"
      shared_state_root_virtiofsd_pid=$started_virtiofsd_pid
    fi
    if [ "$shared_credential_slots_enabled" = "1" ] && [ -n "$shared_credential_slots_host_dir" ]; then
      spawn_virtiofsd "$shared_credential_slots_host_dir" "$shared_credential_slots_socket" "$virtiofsd_shared_credential_slots_log"
      shared_credential_slots_virtiofsd_pid=$started_virtiofsd_pid
    fi
    spawn_virtiofsd "$host_agent_tools_dir" "$agent_tools_socket" "$virtiofsd_agent_tools_log"
    agent_tools_virtiofsd_pid=$started_virtiofsd_pid

    wait_for_virtiofsd_socket "$ro_store_socket" "$virtiofsd_ro_store_log" "$ro_store_virtiofsd_pid"
    trace_wrapper "virtiofs-ro-store-ready"

    wait_for_virtiofsd_socket "$hostcwd_socket" "$virtiofsd_hostcwd_log" "$hostcwd_virtiofsd_pid"
    trace_wrapper "virtiofs-hostcwd-ready"

    wait_for_virtiofsd_socket "$hostruntime_socket" "$virtiofsd_hostruntime_log" "$hostruntime_virtiofsd_pid"
    trace_wrapper "virtiofs-hostruntime-ready"

    if [ -n "${shared_state_root_virtiofsd_pid:-}" ]; then
      wait_for_virtiofsd_socket "$shared_state_root_socket" "$virtiofsd_shared_state_root_log" "$shared_state_root_virtiofsd_pid"
      trace_wrapper "virtiofs-state-root-ready"
    fi

    if [ -n "${shared_credential_slots_virtiofsd_pid:-}" ]; then
      wait_for_virtiofsd_socket "$shared_credential_slots_socket" "$virtiofsd_shared_credential_slots_log" "$shared_credential_slots_virtiofsd_pid"
      trace_wrapper "virtiofs-credential-slots-ready"
    fi

    wait_for_virtiofsd_socket "$agent_tools_socket" "$virtiofsd_agent_tools_log" "$agent_tools_virtiofsd_pid"
    trace_wrapper "virtiofs-agent-tools-ready"
    ;;
  vfkit)
    ;;
  *)
    echo "unsupported local runtime backend: $runtime_backend" >&2
    exit 1
    ;;
esac

if [ "$worker_bridge_enabled" = "1" ]; then
  start_worker_bridge_server
fi

run_runner() {
  if [ "$runtime_backend" = "vfkit" ]; then
    if [ "$agent_session_mode" = "agent-exec" ] || [ "$agent_session_mode" = "agent-attach-exec" ]; then
      env \
        MICROVM_VFKIT_HOST_META_DIR="$host_meta_dir" \
        MICROVM_VFKIT_HOST_CWD_DIR="$host_cwd" \
        MICROVM_VFKIT_SHARED_STATE_ROOT_DIR="$shared_state_root_host_dir" \
        MICROVM_VFKIT_SHARED_CREDENTIAL_SLOTS_DIR="$shared_credential_slots_host_dir" \
        MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR="$host_exec_output_dir" \
        MICROVM_VFKIT_AGENT_TOOLS_DIR="$host_agent_tools_dir" \
        MICROVM_VFKIT_WORKER_BRIDGE_DIR="$worker_bridge_dir" \
        @RUNNER@ "$@"
    else
      env \
        MICROVM_VFKIT_HOST_META_DIR="$host_meta_dir" \
        MICROVM_VFKIT_HOST_CWD_DIR="$host_cwd" \
        MICROVM_VFKIT_SHARED_STATE_ROOT_DIR="$shared_state_root_host_dir" \
        MICROVM_VFKIT_SHARED_CREDENTIAL_SLOTS_DIR="$shared_credential_slots_host_dir" \
        MICROVM_VFKIT_AGENT_TOOLS_DIR="$host_agent_tools_dir" \
        MICROVM_VFKIT_WORKER_BRIDGE_DIR="$worker_bridge_dir" \
        @RUNNER@ "$@"
    fi
    return
  fi

  if [ "$runtime_backend" != "cloud-hypervisor" ]; then
    echo "unsupported local runtime backend: $runtime_backend" >&2
    exit 1
  fi

  if [ "$agent_session_mode" = "agent-exec" ] || [ "$agent_session_mode" = "agent-attach-exec" ]; then
    env \
      MICROVM_RO_STORE_SOCKET="$ro_store_socket" \
      MICROVM_CLOUD_HYPERVISOR_TAP_INTERFACE="$cloud_hypervisor_tap_interface" \
      MICROVM_HOST_RUNTIME_SOCKET="$hostruntime_socket" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_SHARED_STATE_ROOT_DIR="$shared_state_root_host_dir" \
      MICROVM_SHARED_STATE_ROOT_SOCKET="$shared_state_root_socket" \
      MICROVM_SHARED_CREDENTIAL_SLOTS_DIR="$shared_credential_slots_host_dir" \
      MICROVM_SHARED_CREDENTIAL_SLOTS_SOCKET="$shared_credential_slots_socket" \
      MICROVM_AGENT_TOOLS_SOCKET="$agent_tools_socket" \
      @RUNNER@ "$@"
  else
    env \
      MICROVM_RO_STORE_SOCKET="$ro_store_socket" \
      MICROVM_CLOUD_HYPERVISOR_TAP_INTERFACE="$cloud_hypervisor_tap_interface" \
      MICROVM_HOST_RUNTIME_SOCKET="$hostruntime_socket" \
      MICROVM_HOST_CWD_SOCKET="$hostcwd_socket" \
      MICROVM_SHARED_STATE_ROOT_DIR="$shared_state_root_host_dir" \
      MICROVM_SHARED_STATE_ROOT_SOCKET="$shared_state_root_socket" \
      MICROVM_SHARED_CREDENTIAL_SLOTS_DIR="$shared_credential_slots_host_dir" \
      MICROVM_SHARED_CREDENTIAL_SLOTS_SOCKET="$shared_credential_slots_socket" \
      MICROVM_AGENT_TOOLS_SOCKET="$agent_tools_socket" \
      @RUNNER@ "$@"
  fi
}

runner_status=0
trace_wrapper "runner-start"
if [ "$agent_session_mode" = "agent-exec" ]; then
  (
    cd "$runner_workdir"
    run_runner "$@"
  ) >"$runner_stdout_log" 2>"$runner_stderr_log" || runner_status=$?
elif [ "$agent_session_mode" = "agent-attach-exec" ]; then
  attach_runner_script=$host_runtime_dir/attached-runner.sh
  attach_relay_script=$host_runtime_dir/attach-relay.py
  attach_driver_script=$host_runtime_dir/attach-driver.py
  quoted_runner_args=""
  for arg in "$@"; do
    printf -v quoted_runner_arg '%q' "$arg"
    quoted_runner_args="$quoted_runner_args $quoted_runner_arg"
  done
  cat >"$attach_runner_script" <<EOF
set -eu
cd '$(printf '%s' "$runner_workdir" | sed "s/'/'\\''/g")'
export MICROVM_RO_STORE_SOCKET='$(printf '%s' "$ro_store_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_CLOUD_HYPERVISOR_TAP_INTERFACE='$(printf '%s' "$cloud_hypervisor_tap_interface" | sed "s/'/'\\\\''/g")'
export MICROVM_HOST_RUNTIME_SOCKET='$(printf '%s' "$hostruntime_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_HOST_CWD_SOCKET='$(printf '%s' "$hostcwd_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_SHARED_STATE_ROOT_DIR='$(printf '%s' "$shared_state_root_host_dir" | sed "s/'/'\\\\''/g")'
export MICROVM_SHARED_STATE_ROOT_SOCKET='$(printf '%s' "$shared_state_root_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_SHARED_CREDENTIAL_SLOTS_DIR='$(printf '%s' "$shared_credential_slots_host_dir" | sed "s/'/'\\\\''/g")'
export MICROVM_SHARED_CREDENTIAL_SLOTS_SOCKET='$(printf '%s' "$shared_credential_slots_socket" | sed "s/'/'\\\\''/g")'
export MICROVM_AGENT_TOOLS_SOCKET='$(printf '%s' "$agent_tools_socket" | sed "s/'/'\\\\''/g")'
exec @RUNNER@$quoted_runner_args
EOF
  chmod 0555 "$attach_runner_script"
  cat >"$attach_relay_script" <<'EOF'
import os
from datetime import datetime, timezone

stdout_log_path = os.environ["FIREBREAK_ATTACH_STDOUT_LOG"]
bridge_trace_path = os.environ.get("FIREBREAK_WORKER_BRIDGE_TRACE_PATH", "")
wrapper_trace_log = os.environ.get("FIREBREAK_WRAPPER_TRACE_LOG", "")
attach_stage_path = os.environ.get("FIREBREAK_ATTACH_STAGE_PATH", "")
command_signal_stream_path = os.environ.get("FIREBREAK_ATTACH_COMMAND_SIGNAL_STREAM", "")

def trace_event(target_path: str, message: str) -> None:
    if not target_path:
        return
    with open(target_path, "a", encoding="utf-8") as handle:
        handle.write(message + "\n")


def current_attach_stage() -> str:
    if not attach_stage_path:
        return ""
    try:
        return open(attach_stage_path, "r", encoding="utf-8").read().strip()
    except OSError:
        return ""


def append_command_signal(signal_name: str) -> None:
    if not command_signal_stream_path:
        return
    try:
        with open(command_signal_stream_path, "a", encoding="utf-8") as handle:
            handle.write(signal_name + "\n")
    except OSError:
        pass
EOF
  chmod 0555 "$attach_relay_script"
  cat >"$attach_driver_script" <<'EOF'
import importlib.util
import fcntl
import os
import pty
import signal
import struct
import sys
import termios
import threading
import time
from datetime import datetime, timezone

runner_script = os.environ["FIREBREAK_ATTACH_RUNNER_SCRIPT"]
stdout_log_path = os.environ["FIREBREAK_ATTACH_STDOUT_LOG"]
status_path = os.environ["FIREBREAK_ATTACH_STATUS_PATH"]
relay_path = os.environ["FIREBREAK_ATTACH_RELAY_PATH"]
attach_trace_log = os.environ.get("FIREBREAK_ATTACH_TRACE_LOG", "")

relay_spec = importlib.util.spec_from_file_location("firebreak_attach_relay", relay_path)
relay = importlib.util.module_from_spec(relay_spec)
assert relay_spec.loader is not None
relay_spec.loader.exec_module(relay)

child_pid = None
master_fd = None
stdin_done = threading.Event()
stdout_done = threading.Event()
terminal_rows = 24
terminal_columns = 80
focus_tracking_enabled = False
focus_in_sent = False
kitty_keyboard_flags = 0
kitty_keyboard_stack = []
terminal_state = {"row": 1, "column": 1}
terminal_query_buffer = bytearray()
stdin_reply_buffer = bytearray()
command_start_marker_seen = False
command_stream_stage = ""
repeated_interrupt_state = {"last_at": None}
command_interrupt_state = {"requested_at": None, "term_sent_at": None, "kill_sent": False}
terminal_queries = [
    (b"\x1b[6n", "cursor"),
    (b"\x1b[5n", "status"),
    (b"\x1b[?u", "kitty-kbd-query"),
    (b"\x1b[c", "da1"),
    (b"\x1b]10;?\x1b\\", "osc10"),
    (b"\x1b]10;?\x07", "osc10"),
    (b"\x1b]11;?\x1b\\", "osc11"),
    (b"\x1b]11;?\x07", "osc11"),
]
sync_output_dcs_sequences = {
    b"\x1bP=1s\x1b\\": "sync-output-begin",
    b"\x1bP=2s\x1b\\": "sync-output-end",
}
command_exit_grace_started_at = None
runner_term_sent_at = None
runner_kill_sent = False


def query_terminal_size():
    for fd in (sys.stdin.fileno(), sys.stdout.fileno()):
        try:
            size = os.get_terminal_size(fd)
            if size.lines > 0 and size.columns > 0:
                return size.lines, size.columns
        except OSError:
            continue
    return 24, 80


def apply_terminal_size() -> None:
    global terminal_rows, terminal_columns
    terminal_rows, terminal_columns = query_terminal_size()
    if master_fd is None or master_fd < 0:
        return
    winsize = struct.pack("HHHH", terminal_rows, terminal_columns, 0, 0)
    try:
        fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
    except (OSError, ValueError):
        pass


def longest_query_prefix(data: bytes) -> int:
    longest = 0
    for pattern, _ in terminal_queries:
        max_prefix = min(len(pattern) - 1, len(data))
        while max_prefix > longest:
            if data.endswith(pattern[:max_prefix]):
                longest = max_prefix
                break
            max_prefix -= 1
    return longest


def consume_terminal_sequence(data: bytes, index: int):
    if data[index] != 0x1B:
        return None, index + 1, None
    if index + 1 >= len(data):
        return None, index, "incomplete"

    next_byte = data[index + 1]
    if next_byte == 0x5B:
        seq_end = index + 2
        while seq_end < len(data) and not (0x40 <= data[seq_end] <= 0x7E):
            seq_end += 1
        if seq_end >= len(data):
            return None, index, "incomplete"
        return bytes(data[index:seq_end + 1]), seq_end + 1, "csi"
    if next_byte == 0x5D:
        osc_end_bel = data.find(b"\x07", index + 2)
        osc_end_st = data.find(b"\x1b\\", index + 2)
        end_candidates = [end for end in (osc_end_bel, osc_end_st) if end >= 0]
        if not end_candidates:
            return None, index, "incomplete"
        end_index = min(end_candidates)
        if end_index == osc_end_bel:
            return bytes(data[index:end_index + 1]), end_index + 1, "osc"
        return bytes(data[index:end_index + 2]), end_index + 2, "osc"
    if next_byte == 0x50:
        dcs_end = data.find(b"\x1b\\", index + 2)
        if dcs_end < 0:
            return None, index, "incomplete"
        return bytes(data[index:dcs_end + 2]), dcs_end + 2, "dcs"
    if next_byte == 0x1B:
        return None, index + 1, "escaped-esc"
    return bytes(data[index:index + 2]), index + 2, "esc"


def clamp_cursor() -> None:
    terminal_state["row"] = max(1, min(terminal_state["row"], terminal_rows))
    terminal_state["column"] = max(1, min(terminal_state["column"], terminal_columns))


def parse_cursor_params(raw_params: str):
    params = []
    for item in raw_params.split(";"):
        if item == "":
            params.append(None)
            continue
        digits = "".join(ch for ch in item if ch.isdigit())
        params.append(int(digits) if digits else None)
    return params


def trace_debug(message: str) -> None:
    if attach_trace_log:
        relay.trace_event(
            attach_trace_log,
            f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} {message}",
        )
    if relay.bridge_trace_path:
        relay.trace_event(relay.bridge_trace_path, message)


def handle_command_start_marker() -> None:
    global focus_in_sent, command_start_marker_seen, focus_tracking_enabled, kitty_keyboard_flags, command_stream_stage
    command_start_marker_seen = True
    command_stream_stage = "command-start"
    stdin_reply_buffer.clear()
    terminal_query_buffer.clear()
    repeated_interrupt_state["last_at"] = None
    command_interrupt_state["requested_at"] = None
    command_interrupt_state["term_sent_at"] = None
    command_interrupt_state["kill_sent"] = False
    kitty_keyboard_stack.clear()
    kitty_keyboard_flags = 0
    terminal_state["row"] = 1
    terminal_state["column"] = 1
    focus_tracking_enabled = False
    focus_in_sent = False
    trace_debug("command-stream-marker")


def current_command_stage() -> str:
    stage = relay.current_attach_stage()
    if stage.startswith("command-exit:"):
        return stage
    if command_stream_stage.startswith("command-exit:"):
        return command_stream_stage
    if stage:
        return stage
    return command_stream_stage


def command_stage_active() -> bool:
    stage = current_command_stage()
    return command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:")


def handle_firebreak_stream_marker(sequence: bytes) -> bool:
    global command_stream_stage
    prefix = b"\x1b]9001;firebreak;"
    if not sequence.startswith(prefix):
        return False
    if sequence.endswith(b"\x07"):
        payload = sequence[len(prefix):-1]
    elif sequence.endswith(b"\x1b\\"):
        payload = sequence[len(prefix):-2]
    else:
        return False
    marker = payload.decode("ascii", "ignore")
    if not marker:
        return True
    command_stream_stage = marker
    trace_debug(f"command-stream-marker:{marker}")
    if marker == "command-start" and not command_start_marker_seen:
        handle_command_start_marker()
    return True


def maybe_escalate_repeated_interrupt(chunk: bytes) -> None:
    if not command_stage_active():
        return
    now = time.monotonic()
    for byte in chunk:
        if byte != 0x03:
            continue
        previous = repeated_interrupt_state["last_at"]
        repeated_interrupt_state["last_at"] = now
        if previous is None or now - previous > 8.0:
            continue
        relay.append_command_signal("INT")
        command_interrupt_state["requested_at"] = now
        command_interrupt_state["term_sent_at"] = None
        command_interrupt_state["kill_sent"] = False
        trace_debug("stdin-signal-request:INT")


def parse_optional_int(raw_value: str, default: int = 0) -> int:
    digits = "".join(ch for ch in raw_value if ch.isdigit())
    if not digits:
        return default
    return int(digits)


def apply_kitty_keyboard_mode(raw_params: str) -> None:
    global kitty_keyboard_flags
    flags_raw, sep, mode_raw = raw_params.partition(";")
    flags = parse_optional_int(flags_raw, default=0)
    mode = parse_optional_int(mode_raw, default=1) if sep else 1
    previous_flags = kitty_keyboard_flags
    if mode == 1:
        kitty_keyboard_flags = flags
    elif mode == 2:
        kitty_keyboard_flags |= flags
    elif mode == 3:
        kitty_keyboard_flags &= ~flags
    trace_debug(
        f"kitty-kbd-set:flags={flags}:mode={mode}:previous={previous_flags}:current={kitty_keyboard_flags}"
    )


def push_kitty_keyboard_flags(raw_value: str) -> None:
    global kitty_keyboard_flags
    flags = parse_optional_int(raw_value, default=0)
    kitty_keyboard_stack.append(kitty_keyboard_flags)
    kitty_keyboard_flags = flags
    trace_debug(
        f"kitty-kbd-push:requested={flags}:stack-depth={len(kitty_keyboard_stack)}:current={kitty_keyboard_flags}"
    )


def pop_kitty_keyboard_flags(raw_value: str) -> None:
    global kitty_keyboard_flags
    pop_count = parse_optional_int(raw_value, default=1)
    if pop_count < 1:
        pop_count = 1
    for _ in range(pop_count):
        if kitty_keyboard_stack:
            kitty_keyboard_flags = kitty_keyboard_stack.pop()
        else:
            kitty_keyboard_flags = 0
            break
    trace_debug(
        f"kitty-kbd-pop:count={pop_count}:stack-depth={len(kitty_keyboard_stack)}:current={kitty_keyboard_flags}"
    )


def update_terminal_cursor(data: bytes) -> None:
    global focus_tracking_enabled, focus_in_sent
    index = 0
    data_length = len(data)
    while index < data_length:
        byte = data[index]
        if byte == 0x0D:
            terminal_state["column"] = 1
            index += 1
            continue
        if byte == 0x0A:
            terminal_state["row"] += 1
            clamp_cursor()
            index += 1
            continue
        if byte == 0x08:
            terminal_state["column"] = max(1, terminal_state["column"] - 1)
            index += 1
            continue
        if byte != 0x1B:
            terminal_state["column"] += 1
            if terminal_state["column"] > terminal_columns:
                terminal_state["column"] = 1
                terminal_state["row"] += 1
            clamp_cursor()
            index += 1
            continue
        if index + 1 >= data_length:
            break
        next_byte = data[index + 1]
        if next_byte == 0x5B:
            seq_end = index + 2
            while seq_end < data_length and not (0x40 <= data[seq_end] <= 0x7E):
                seq_end += 1
            if seq_end >= data_length:
                break
            params = data[index + 2:seq_end].decode("ascii", "ignore")
            final = chr(data[seq_end])
            raw_params = params
            params = parse_cursor_params(raw_params)
            first = params[0] if params else None
            second = params[1] if len(params) > 1 else None
            if final in {"H", "f"}:
                terminal_state["row"] = first if first is not None else 1
                terminal_state["column"] = second if second is not None else 1
                clamp_cursor()
            elif final == "A":
                terminal_state["row"] -= first if first is not None else 1
                clamp_cursor()
            elif final == "B":
                terminal_state["row"] += first if first is not None else 1
                clamp_cursor()
            elif final == "C":
                terminal_state["column"] += first if first is not None else 1
                clamp_cursor()
            elif final == "D":
                terminal_state["column"] -= first if first is not None else 1
                clamp_cursor()
            elif final == "E":
                terminal_state["row"] += first if first is not None else 1
                terminal_state["column"] = 1
                clamp_cursor()
            elif final == "F":
                terminal_state["row"] -= first if first is not None else 1
                terminal_state["column"] = 1
                clamp_cursor()
            elif final == "G":
                terminal_state["column"] = first if first is not None else 1
                clamp_cursor()
            elif final == "d":
                terminal_state["row"] = first if first is not None else 1
                clamp_cursor()
            elif final == "h" and raw_params == "?1004":
                focus_tracking_enabled = True
                focus_in_sent = False
                trace_debug("mode-set:?1004")
            elif final == "l" and raw_params == "?1004":
                focus_tracking_enabled = False
                focus_in_sent = False
                trace_debug("mode-reset:?1004")
            elif final == "h":
                trace_debug(f"mode-set:{raw_params or 'default'}")
            elif final == "l":
                trace_debug(f"mode-reset:{raw_params or 'default'}")
            elif final in {"n", "c"}:
                trace_debug(f"unhandled-csi:{raw_params}{final}")
            index = seq_end + 1
            continue
        if next_byte == 0x5D:
            osc_end_bel = data.find(b"\x07", index + 2)
            osc_end_st = data.find(b"\x1b\\", index + 2)
            end_candidates = [end for end in (osc_end_bel, osc_end_st) if end >= 0]
            if not end_candidates:
                break
            end_index = min(end_candidates)
            if end_index == osc_end_bel:
                index = end_index + 1
            else:
                index = end_index + 2
            continue
        if next_byte == 0x63:
            terminal_state["row"] = 1
            terminal_state["column"] = 1
            index += 2
            continue
        index += 2


def build_terminal_reply(query_name: str) -> bytes:
    if query_name == "cursor":
        clamp_cursor()
        reply = f"\x1b[{terminal_state['row']};{terminal_state['column']}R".encode("ascii")
        trace_debug(f"cursor-reply:{terminal_state['row']};{terminal_state['column']}")
        return reply
    if query_name == "status":
        return b"\x1b[0n"
    if query_name == "kitty-kbd-query":
        return b"\x1b[?0u"
    if query_name == "da1":
        return b"\x1b[?62;1;2;6;22c"
    if query_name == "osc10":
        return b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"
    if query_name == "osc11":
        return b"\x1b]11;rgb:0000/0000/0000\x1b\\"
    return b""


def build_xtgettcap_reply(sequence: bytes) -> bytes:
    if not (sequence.startswith(b"\x1bP+q") and sequence.endswith(b"\x1b\\")):
        return b""

    payload = sequence[4:-2]
    items = payload.split(b";")
    response_items = []
    term_name = os.environ.get("TERM", "xterm-256color").encode("ascii", "ignore") or b"xterm-256color"

    for item in items:
        if not item:
            continue
        try:
            decoded = bytes.fromhex(item.decode("ascii")).decode("ascii").lower()
        except ValueError:
            return b"\x1bP0+r" + payload + b"\x1b\\"

        if decoded in {"name", "tn"}:
            response_items.append(item + b"=" + term_name.hex().encode("ascii"))
            continue
        if decoded in {"colors", "co"}:
            response_items.append(item + b"=" + b"323536")
            continue
        return b"\x1bP0+r" + payload + b"\x1b\\"

    if not response_items:
        return b"\x1bP0+r" + payload + b"\x1b\\"

    return b"\x1bP1+r" + b";".join(response_items) + b"\x1b\\"


def send_focus_in_event() -> None:
    global focus_in_sent
    if not focus_tracking_enabled or focus_in_sent:
        return
    try:
        os.write(master_fd, b"\x1b[I")
        trace_debug("attach-term-reply:focus-in")
        focus_in_sent = True
    except OSError:
        pass


def classify_csi_reply(sequence: bytes):
    if not sequence.startswith(b"\x1b[") or len(sequence) < 3:
        return None
    final = sequence[-1:]
    payload = sequence[2:-1].decode("ascii", "ignore")
    if final == b"R":
        parts = payload.split(";")
        if len(parts) == 2 and all(part.isdigit() for part in parts):
            return "cursor"
    if payload.startswith("?") and final == b"u":
        reply_body = payload[1:]
        if reply_body and all(ch.isdigit() or ch in ";:" for ch in reply_body):
            return "kitty-kbd-reply"
    if payload.startswith("?") and final == b"c":
        reply_body = payload[1:]
        if reply_body and all(ch.isdigit() or ch in ";:" for ch in reply_body):
            return "da1-reply"
    return None


def classify_osc_reply(sequence: bytes):
    if sequence.startswith(b"\x1b]10;"):
        return "osc10-reply"
    if sequence.startswith(b"\x1b]11;"):
        return "osc11-reply"
    return None


def is_partial_reply(data: bytes) -> bool:
    if not data:
        return False
    if data == b"\x1b":
        return True
    if data.startswith(b"\x1b]"):
        return data.startswith((b"\x1b]10;", b"\x1b]11;"))
    if not data.startswith(b"\x1b["):
        return False
    if len(data) == 2:
        return True
    payload = data[2:]
    return all(byte in b"0123456789;:?" for byte in payload)


def strip_terminal_replies(chunk: bytes) -> bytes:
    stdin_reply_buffer.extend(chunk)
    data = bytes(stdin_reply_buffer)
    forwarded = bytearray()
    index = 0

    while index < len(data):
        byte = data[index]
        if byte != 0x1B:
            forwarded.append(byte)
            index += 1
            continue

        if index + 1 >= len(data):
            break

        next_byte = data[index + 1]
        if next_byte == 0x5B:
            seq_end = index + 2
            while seq_end < len(data) and not (0x40 <= data[seq_end] <= 0x7E):
                seq_end += 1
            if seq_end >= len(data):
                break
            sequence = data[index:seq_end + 1]
            reply_name = classify_csi_reply(sequence)
            if reply_name is not None:
                trace_debug(f"stdin-term-reply:{reply_name}:{sequence.hex()}")
                index = seq_end + 1
                continue
            forwarded.extend(sequence)
            index = seq_end + 1
            continue

        if next_byte == 0x5D:
            osc_end_bel = data.find(b"\x07", index + 2)
            osc_end_st = data.find(b"\x1b\\", index + 2)
            end_candidates = [end for end in (osc_end_bel, osc_end_st) if end >= 0]
            if not end_candidates:
                break
            end_index = min(end_candidates)
            if end_index == osc_end_bel:
                sequence = data[index:end_index + 1]
                advance = end_index + 1
            else:
                sequence = data[index:end_index + 2]
                advance = end_index + 2
            reply_name = classify_osc_reply(sequence)
            if reply_name is not None:
                trace_debug(f"stdin-term-reply:{reply_name}:{sequence.hex()}")
                index = advance
                continue
            forwarded.extend(sequence)
            index = advance
            continue

        forwarded.append(byte)
        index += 1

    remainder = data[index:]
    if remainder and not is_partial_reply(remainder):
        forwarded.extend(remainder)
        stdin_reply_buffer.clear()
    else:
        stdin_reply_buffer[:] = remainder

    return bytes(forwarded)


def split_terminal_output(chunk: bytes) -> bytes:
    if not chunk:
        return b""
    terminal_query_buffer.extend(chunk)
    data = bytes(terminal_query_buffer)
    forwarded = bytearray()
    index = 0

    while index < len(data):
        if data[index] == 0x1B:
            sequence, next_index, sequence_type = consume_terminal_sequence(data, index)
            if sequence_type == "incomplete":
                break
            if sequence_type == "escaped-esc":
                index = next_index
                continue
            if sequence_type == "osc" and sequence is not None and handle_firebreak_stream_marker(sequence):
                index = next_index
                continue
            if sequence_type == "dcs" and sequence in sync_output_dcs_sequences:
                trace_debug(sync_output_dcs_sequences[sequence])
                index = next_index
                continue
            if sequence_type == "dcs" and sequence is not None and sequence.startswith(b"\x1bP+q"):
                response = build_xtgettcap_reply(sequence)
                if response:
                    try:
                        os.write(master_fd, response)
                        trace_debug("attach-term-reply:xtgettcap")
                    except OSError:
                        pass
                index = next_index
                continue
            if sequence_type == "csi" and sequence is not None and sequence.endswith(b"u"):
                raw_params = sequence[2:-1].decode("ascii", "ignore")
                if raw_params.startswith(">"):
                    push_kitty_keyboard_flags(raw_params[1:])
                    index = next_index
                    continue
                if raw_params.startswith("<"):
                    pop_kitty_keyboard_flags(raw_params[1:])
                    index = next_index
                    continue
                if raw_params.startswith("="):
                    apply_kitty_keyboard_mode(raw_params[1:])
                    index = next_index
                    continue
            if sequence_type == "csi" and sequence is not None:
                raw_params = sequence[2:-1].decode("ascii", "ignore")
                final = chr(sequence[-1])
                if raw_params == "?2026" and final == "h":
                    trace_debug("mode-set:?2026")
                    index = next_index
                    continue
                if raw_params == "?2026" and final == "l":
                    trace_debug("mode-reset:?2026")
                    index = next_index
                    continue

            matched_query = False
            if sequence is not None:
                for pattern, query_name in terminal_queries:
                    if sequence != pattern:
                        continue
                    response = build_terminal_reply(query_name)
                    if response:
                        try:
                            os.write(master_fd, response)
                            trace_debug(f"attach-term-reply:{query_name}")
                        except OSError:
                            pass
                    index = next_index
                    matched_query = True
                    break
            if matched_query:
                continue

            if sequence is not None:
                forwarded.extend(sequence)
                index = next_index
                continue

        matched_query = False
        for pattern, query_name in terminal_queries:
            if data.startswith(pattern, index):
                response = build_terminal_reply(query_name)
                if response:
                    try:
                        os.write(master_fd, response)
                        trace_debug(f"attach-term-reply:{query_name}")
                    except OSError:
                        pass
                index += len(pattern)
                matched_query = True
                break
        if matched_query:
            continue
        forwarded.append(data[index])
        index += 1

    remainder = data[index:]
    terminal_query_buffer[:] = remainder
    stage = current_command_stage()
    if remainder and (command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:")):
        trace_debug(f"command-output-remainder:{remainder[:32].hex()}")
    forwarded_bytes = bytes(forwarded)
    if forwarded_bytes:
        update_terminal_cursor(forwarded_bytes)
    return forwarded_bytes


def pump_stdin() -> None:
    global master_fd
    first_input = True
    try:
        while True:
            try:
                chunk = os.read(sys.stdin.fileno(), 4096)
            except OSError:
                break
            if not chunk:
                try:
                    os.close(master_fd)
                except OSError:
                    pass
                master_fd = -1
                break
            chunk = strip_terminal_replies(chunk)
            if not chunk:
                continue
            if first_input:
                first_input = False
                trace_debug(f"stdin-first-chunk-len:{len(chunk)}")
            else:
                trace_debug(f"stdin-sample-len:{len(chunk[:16])}")
            maybe_escalate_repeated_interrupt(chunk)
            try:
                os.write(master_fd, chunk)
            except OSError:
                break
    finally:
        stdin_done.set()


def pump_stdout() -> None:
    first_chunk = True
    command_output_chunk_seen = False
    command_stage_initialized = False
    raw_sample_count = 0
    filtered_empty_sample_count = 0
    command_raw_sample_count = 0
    command_filtered_empty_sample_count = 0
    command_forwarded_sample_count = 0
    try:
        with open(stdout_log_path, "ab", buffering=0) as log_handle:
            while True:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                raw_chunk = chunk
                if raw_sample_count < 8:
                    trace_debug(f"stdout-raw-sample:{raw_chunk[:64].hex()}")
                    raw_sample_count += 1
                stage = current_command_stage()
                if stage == "command-start" and not command_start_marker_seen:
                    handle_command_start_marker()
                if (command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:")) and command_raw_sample_count < 8:
                    trace_debug(f"command-stdout-raw-sample:{raw_chunk[:64].hex()}")
                    command_raw_sample_count += 1
                chunk = split_terminal_output(raw_chunk)
                stage = current_command_stage()
                if (command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:")) and not command_stage_initialized:
                    command_stage_initialized = True
                send_focus_in_event()
                if not chunk:
                    if filtered_empty_sample_count < 8:
                        trace_debug("stdout-filtered-empty")
                        filtered_empty_sample_count += 1
                    if (command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:")) and command_filtered_empty_sample_count < 8:
                        trace_debug("command-stdout-filtered-empty")
                        command_filtered_empty_sample_count += 1
                    continue
                if first_chunk:
                    first_chunk = False
                    if relay.wrapper_trace_log:
                        relay.trace_event(
                            relay.wrapper_trace_log,
                            f"{relay.datetime.now(relay.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} runner-stdout-first-byte",
                        )
                    if relay.bridge_trace_path:
                        relay.trace_event(relay.bridge_trace_path, "nested-runner-first-byte")
                if not command_output_chunk_seen and (command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:")):
                    command_output_chunk_seen = True
                    if relay.wrapper_trace_log:
                        relay.trace_event(
                            relay.wrapper_trace_log,
                            f"{relay.datetime.now(relay.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} command-stdout-first-byte",
                        )
                    if relay.bridge_trace_path:
                        relay.trace_event(relay.bridge_trace_path, "nested-command-first-byte")
                if (
                    (command_start_marker_seen or stage == "command-start" or stage.startswith("command-exit:"))
                    and command_forwarded_sample_count < 16
                ):
                    trace_debug(f"command-stdout-forwarded-sample:{chunk[:64].hex()}")
                    command_forwarded_sample_count += 1
                log_handle.write(chunk)
                try:
                    os.write(sys.stdout.fileno(), chunk)
                except OSError:
                    break
    finally:
        stdout_done.set()


def forward_signal(signum, _frame) -> None:
    if child_pid is None:
        return
    try:
        os.kill(child_pid, signum)
    except OSError:
        pass


for signum in (signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, forward_signal)


def handle_sigwinch(_signum, _frame) -> None:
    apply_terminal_size()


signal.signal(signal.SIGWINCH, handle_sigwinch)


def wait_for_child_exit():
    global command_exit_grace_started_at, runner_term_sent_at, runner_kill_sent
    while True:
        try:
            waited_pid, wait_status = os.waitpid(child_pid, os.WNOHANG)
        except ChildProcessError:
            return 1
        if waited_pid == child_pid:
            return wait_status

        stage = current_command_stage()
        now = time.monotonic()
        if (
            stage == "command-start"
            and command_interrupt_state["requested_at"] is not None
        ):
            if (
                command_interrupt_state["term_sent_at"] is None
                and now - command_interrupt_state["requested_at"] >= 3.0
            ):
                relay.append_command_signal("TERM")
                command_interrupt_state["term_sent_at"] = now
                trace_debug("stdin-signal-request:TERM")
            elif (
                command_interrupt_state["term_sent_at"] is not None
                and not command_interrupt_state["kill_sent"]
                and now - command_interrupt_state["term_sent_at"] >= 5.0
            ):
                relay.append_command_signal("KILL")
                command_interrupt_state["kill_sent"] = True
                trace_debug("stdin-signal-request:KILL")
        if stage.startswith("command-exit:"):
            if command_exit_grace_started_at is None:
                command_exit_grace_started_at = now
                trace_debug(f"runner-command-exit-seen:{stage}")
            elif runner_term_sent_at is None and now - command_exit_grace_started_at >= 3.0:
                try:
                    os.kill(child_pid, signal.SIGTERM)
                    runner_term_sent_at = now
                    trace_debug("runner-signal:TERM-after-command-exit")
                except OSError:
                    pass
            elif (
                runner_term_sent_at is not None
                and not runner_kill_sent
                and now - runner_term_sent_at >= 5.0
            ):
                try:
                    os.kill(child_pid, signal.SIGKILL)
                    runner_kill_sent = True
                    trace_debug("runner-signal:KILL-after-command-exit")
                except OSError:
                    pass
        time.sleep(0.1)

child_pid, master_fd = pty.fork()
if child_pid == 0:
    os.execvpe("bash", ["bash", runner_script], os.environ.copy())

apply_terminal_size()

stdin_thread = threading.Thread(target=pump_stdin, daemon=True)
stdout_thread = threading.Thread(target=pump_stdout, daemon=True)
stdin_thread.start()
stdout_thread.start()

wait_status = wait_for_child_exit()
stdin_done.set()
stdout_done.set()
stdin_thread.join(timeout=1)
stdout_thread.join(timeout=5)
try:
    os.close(master_fd)
except OSError:
    pass
master_fd = -1

if os.WIFEXITED(wait_status):
    exit_code = os.WEXITSTATUS(wait_status)
elif os.WIFSIGNALED(wait_status):
    exit_code = 128 + os.WTERMSIG(wait_status)
else:
    exit_code = 1

with open(status_path, "w", encoding="utf-8") as handle:
    handle.write(f"{exit_code}\n")

raise SystemExit(exit_code)
EOF
  chmod 0555 "$attach_driver_script"
  rm -f "$runner_stdout_log"
  attach_pipe_status_file=$host_runtime_dir/attach-runner.status
  rm -f "$attach_pipe_status_file"
  export FIREBREAK_ATTACH_STDOUT_LOG="$runner_stdout_log"
  export FIREBREAK_ATTACH_TRACE_LOG="$attach_pty_log"
  export FIREBREAK_WRAPPER_TRACE_LOG="$wrapper_trace_log"
  export FIREBREAK_ATTACH_STAGE_PATH="$host_exec_output_dir/attach_stage"
  export FIREBREAK_ATTACH_COMMAND_SIGNAL_STREAM="$host_exec_output_dir/command-signals.stream"
  export FIREBREAK_ATTACH_RUNNER_SCRIPT="$attach_runner_script"
  export FIREBREAK_ATTACH_RELAY_PATH="$attach_relay_script"
  export FIREBREAK_ATTACH_STATUS_PATH="$attach_pipe_status_file"
  python3 "$attach_driver_script" || runner_status=$?
  if [ -f "$attach_pipe_status_file" ]; then
    IFS= read -r attach_pipe_status < "$attach_pipe_status_file" || attach_pipe_status=$runner_status
    case "$attach_pipe_status" in
      ''|*[!0-9]*)
        attach_pipe_status=$runner_status
        ;;
    esac
    runner_status=$attach_pipe_status
  fi
else
  (
    cd "$runner_workdir"
    run_runner "$@"
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
      if [ -s "$virtiofsd_shared_state_root_log" ]; then
        cat "$virtiofsd_shared_state_root_log" >&2
      fi
      if [ -s "$virtiofsd_shared_credential_slots_log" ]; then
        cat "$virtiofsd_shared_credential_slots_log" >&2
      fi
      if [ -s "$virtiofsd_hostruntime_log" ]; then
        cat "$virtiofsd_hostruntime_log" >&2
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
  if [ -s "$virtiofsd_shared_state_root_log" ]; then
    cat "$virtiofsd_shared_state_root_log" >&2
  fi
  if [ -s "$virtiofsd_shared_credential_slots_log" ]; then
    cat "$virtiofsd_shared_credential_slots_log" >&2
  fi
  if [ -s "$virtiofsd_hostruntime_log" ]; then
    cat "$virtiofsd_hostruntime_log" >&2
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
