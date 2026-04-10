set -eu

@FIREBREAK_WORKER_COMMAND_REQUEST_LIB@
@FIREBREAK_PROFILE_LIB@

metadata=@HOST_META_MOUNT@/mount-path
session_mode=tool
session_command_file=@HOST_META_MOUNT@/worker-command
session_mode_file=@HOST_META_MOUNT@/worker-session-mode
session_term_file=@HOST_META_MOUNT@/worker-term
session_columns_file=@HOST_META_MOUNT@/worker-columns
session_lines_file=@HOST_META_MOUNT@/worker-lines
worker_mode_file=@HOST_META_MOUNT@/worker-mode
worker_modes_file=@HOST_META_MOUNT@/worker-modes
tool_runtimes_enabled=@TOOL_RUNTIMES_ENABLED@
tool_runtimes_mount=@TOOL_RUNTIMES_MOUNT@
start_dir=@WORKSPACE_MOUNT@
worker_bridge_enabled=@WORKER_BRIDGE_ENABLED@
guest_state_dir=/run/firebreak-worker
bootstrap_state_local=$guest_state_dir/bootstrap-state.json
command_state_local=$guest_state_dir/command-state.json
session_term_state_file=$guest_state_dir/session-term
session_columns_state_file=$guest_state_dir/session-columns
session_lines_state_file=$guest_state_dir/session-lines
worker_mode_state_file=$guest_state_dir/worker-mode
worker_modes_state_file=$guest_state_dir/worker-modes
request_command_present=0

export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT=@SHARED_STATE_ROOT_HOST_MOUNT@
export FIREBREAK_SHARED_STATE_ROOT_VM_ROOT=@SHARED_STATE_ROOT_VM_ROOT@
export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG=@SHARED_STATE_ROOT_MOUNTED_FLAG@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_HOST_MOUNT=@SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG=@SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@

log_phase() {
  phase=$1
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s %s\n' "[firebreak-session]" "$timestamp $phase"
  firebreak_profile_guest_mark prepare-worker-session "$phase"
}

sync_guest_state_files() {
  if ! [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
    return 0
  fi
  mkdir -p "$guest_state_dir"
  printf '%s\n' '{}' > "$bootstrap_state_local"
  printf '%s\n' '{}' > "$command_state_local"
  chmod 0644 "$bootstrap_state_local" "$command_state_local"
  rm -f @COMMAND_OUTPUT_MOUNT@/bootstrap-state.json @COMMAND_OUTPUT_MOUNT@/command-state.json
  cp "$bootstrap_state_local" @COMMAND_OUTPUT_MOUNT@/bootstrap-state.json
  cp "$command_state_local" @COMMAND_OUTPUT_MOUNT@/command-state.json
  chmod 0666 @COMMAND_OUTPUT_MOUNT@/bootstrap-state.json @COMMAND_OUTPUT_MOUNT@/command-state.json
}

if ! [ -d @WORKSPACE_MOUNT@ ]; then
  echo "workspace mount is unavailable at @WORKSPACE_MOUNT@" >&2
  exit 1
fi

if ! [ -r "$metadata" ]; then
  echo "host cwd metadata is unavailable at $metadata" >&2
  exit 1
fi

log_phase prepare-worker-session-start
log_phase prepare-worker-session-adopt-host-identity-start
@ADOPT_HOST_IDENTITY_SCRIPT@
log_phase prepare-worker-session-adopt-host-identity-done
log_phase prepare-worker-session-metadata-ready
candidate=$(cat "$metadata")
if [ -z "$candidate" ]; then
  echo "host cwd metadata file is empty: $metadata" >&2
  exit 1
fi
start_dir=$candidate

if [ -r "$session_mode_file" ]; then
  session_mode=$(cat "$session_mode_file")
fi

if [ "$session_mode" = "command-exec" ] || [ "$session_mode" = "command-attach-exec" ]; then
  ensure_command_request_loaded
  request_command_present=1
  session_mode=$command_request_session_mode
  if [ -n "$command_request_start_dir" ]; then
    start_dir=$command_request_start_dir
  fi
fi

printf '%s\n' "$start_dir" > @START_DIR_FILE@
chmod 0644 @START_DIR_FILE@

printf '%s\n' "$session_mode" > @SESSION_MODE_FILE@
chmod 0644 @SESSION_MODE_FILE@

if [ "$session_mode" = "command-exec" ] || [ "$session_mode" = "command-attach-exec" ] || [ "$session_mode" = "command-service" ]; then
  log_phase prepare-worker-session-exec-output-ready-check
  if ! [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
    echo "command output share is unavailable at @COMMAND_OUTPUT_MOUNT@" >&2
    exit 1
  fi
  sync_guest_state_files
  if [ "$session_mode" != "command-service" ]; then
    printf '%s\n' "prepare-worker-session-mounted-exec-output" > @COMMAND_OUTPUT_MOUNT@/attach_stage
    chmod 0666 @COMMAND_OUTPUT_MOUNT@/attach_stage
  fi
fi

log_phase prepare-worker-session-state-dir-start
mkdir -p "$guest_state_dir"
@CHOWN@ @DEV_USER@:@DEV_USER@ "$guest_state_dir"
if [ -e "$bootstrap_state_local" ]; then
  @CHOWN@ @DEV_USER@:@DEV_USER@ "$bootstrap_state_local"
fi
if [ -e "$command_state_local" ]; then
  @CHOWN@ @DEV_USER@:@DEV_USER@ "$command_state_local"
fi
rm -f \
  "$session_term_state_file" \
  "$session_columns_state_file" \
  "$session_lines_state_file" \
  "$worker_mode_state_file" \
  "$worker_modes_state_file"
log_phase prepare-worker-session-state-dir-done
if [ "$request_command_present" = "1" ] && [ -n "${command_request_term:-}" ]; then
  printf '%s\n' "$command_request_term" > "$session_term_state_file"
  chmod 0644 "$session_term_state_file"
elif [ -r "$session_term_file" ]; then
  cat "$session_term_file" > "$session_term_state_file"
  chmod 0644 "$session_term_state_file"
fi
if [ "$request_command_present" = "1" ] && [ -n "${command_request_columns:-}" ]; then
  printf '%s\n' "$command_request_columns" > "$session_columns_state_file"
  chmod 0644 "$session_columns_state_file"
elif [ -r "$session_columns_file" ]; then
  cat "$session_columns_file" > "$session_columns_state_file"
  chmod 0644 "$session_columns_state_file"
fi
if [ "$request_command_present" = "1" ] && [ -n "${command_request_lines:-}" ]; then
  printf '%s\n' "$command_request_lines" > "$session_lines_state_file"
  chmod 0644 "$session_lines_state_file"
elif [ -r "$session_lines_file" ]; then
  cat "$session_lines_file" > "$session_lines_state_file"
  chmod 0644 "$session_lines_state_file"
fi
if [ -r "$worker_mode_file" ]; then
  cat "$worker_mode_file" > "$worker_mode_state_file"
  chmod 0644 "$worker_mode_state_file"
fi
if [ -r "$worker_modes_file" ]; then
  cat "$worker_modes_file" > "$worker_modes_state_file"
  chmod 0644 "$worker_modes_state_file"
fi

if [ "$tool_runtimes_enabled" = "1" ]; then
  log_phase prepare-worker-session-mount-tool-runtimes-start
  mkdir -p "$tool_runtimes_mount"
  if ! mountpoint -q "$tool_runtimes_mount"; then
    if ! mount -t virtiofs -o exec hosttoolruntimes "$tool_runtimes_mount"; then
      echo "failed to mount host tool runtimes share" >&2
      exit 1
    fi
  fi
  log_phase prepare-worker-session-mount-tool-runtimes-done
fi

if [ "$worker_bridge_enabled" = "1" ]; then
  log_phase prepare-worker-session-worker-bridge-ready-check
  if ! [ -d @WORKER_BRIDGE_MOUNT@ ]; then
    echo "Firebreak worker bridge share is unavailable at @WORKER_BRIDGE_MOUNT@" >&2
    exit 1
  fi
fi

if [ "$request_command_present" = "1" ]; then
  log_phase prepare-worker-session-command-request-start
  printf '%s\n' "$command_request_command" > @COMMAND_FILE@
  chmod 0644 @COMMAND_FILE@
  sync_guest_state_files
  if [ "$session_mode" = "command-attach-exec" ]; then
    printf '%s\n' "prepare-worker-session-command-ready" > @COMMAND_OUTPUT_MOUNT@/attach_stage
    chmod 0666 @COMMAND_OUTPUT_MOUNT@/attach_stage
  fi
  log_phase prepare-worker-session-command-request-done
elif [ -r "$session_command_file" ]; then
  log_phase prepare-worker-session-command-file-start
  cat "$session_command_file" > @COMMAND_FILE@
  chmod 0644 @COMMAND_FILE@
  sync_guest_state_files
  if [ "$session_mode" = "command-attach-exec" ]; then
    printf '%s\n' "prepare-worker-session-command-ready" > @COMMAND_OUTPUT_MOUNT@/attach_stage
    chmod 0666 @COMMAND_OUTPUT_MOUNT@/attach_stage
  fi
  log_phase prepare-worker-session-command-file-done
fi

if [ "$start_dir" != "@WORKSPACE_MOUNT@" ]; then
  log_phase prepare-worker-session-bind-workspace-start
  if [ -L "$start_dir" ]; then
    rm -f "$start_dir"
  fi

  if ! [ -L "$start_dir" ]; then
    parent=$(dirname "$start_dir")
    mkdir -p "$parent"

    if [ -d "$start_dir" ]; then
      if mountpoint -q "$start_dir"; then
        echo "refusing to replace existing mountpoint: $start_dir" >&2
        exit 1
      fi
      if ! rmdir "$start_dir" 2>/dev/null; then
        echo "refusing to replace existing non-empty directory path: $start_dir" >&2
        exit 1
      fi
    elif [ -e "$start_dir" ]; then
      echo "refusing to replace existing non-directory path: $start_dir" >&2
      exit 1
    fi

    ln -s @WORKSPACE_MOUNT@ "$start_dir"
  fi
  log_phase prepare-worker-session-bind-workspace-done
fi

if [ "@SHARED_STATE_ROOT_ENABLED@" = "1" ]; then
  mkdir -p @SHARED_STATE_ROOT_HOST_MOUNT@ @SHARED_STATE_ROOT_FRESH_ROOT@
  chown @DEV_USER@:@DEV_USER@ @SHARED_STATE_ROOT_FRESH_ROOT@
  rm -f @SHARED_STATE_ROOT_MOUNTED_FLAG@

  if mountpoint -q @SHARED_STATE_ROOT_HOST_MOUNT@; then
    touch @SHARED_STATE_ROOT_MOUNTED_FLAG@
  elif mount_output=$(mount -t virtiofs hoststateroot @SHARED_STATE_ROOT_HOST_MOUNT@ 2>&1); then
    touch @SHARED_STATE_ROOT_MOUNTED_FLAG@
  else
    printf '%s\n' "failed to mount Firebreak shared state root: $mount_output" >&2
    exit 1
  fi
fi

if [ "@SHARED_CREDENTIAL_SLOTS_ENABLED@" = "1" ]; then
  mkdir -p @SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@
  rm -f @SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@

  if mountpoint -q @SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@; then
    touch @SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@
  elif mount_output=$(mount -t virtiofs hostcredentialslots @SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@ 2>&1); then
    touch @SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@
  else
    printf '%s\n' "failed to mount Firebreak shared credential slots: $mount_output" >&2
    exit 1
  fi
fi
log_phase prepare-worker-session-done
