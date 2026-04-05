set -eu

metadata=@HOST_META_MOUNT@/mount-path
session_mode=agent
session_command_file=@HOST_META_MOUNT@/worker-command
session_mode_file=@HOST_META_MOUNT@/worker-session-mode
session_term_file=@HOST_META_MOUNT@/worker-term
session_columns_file=@HOST_META_MOUNT@/worker-columns
session_lines_file=@HOST_META_MOUNT@/worker-lines
worker_mode_file=@HOST_META_MOUNT@/worker-mode
worker_modes_file=@HOST_META_MOUNT@/worker-modes
agent_tools_enabled=@AGENT_TOOLS_ENABLED@
agent_tools_mount=@AGENT_TOOLS_MOUNT@
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

export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT=@SHARED_STATE_ROOT_HOST_MOUNT@
export FIREBREAK_SHARED_STATE_ROOT_VM_ROOT=@SHARED_STATE_ROOT_VM_ROOT@
export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG=@SHARED_STATE_ROOT_MOUNTED_FLAG@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_HOST_MOUNT=@SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG=@SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@

log_phase() {
  phase=$1
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s %s\n' "[firebreak-session]" "$timestamp $phase"
}

sync_guest_state_files() {
  if ! [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
    return 0
  fi
  mkdir -p "$guest_state_dir"
  printf '%s\n' '{}' > "$bootstrap_state_local"
  printf '%s\n' '{}' > "$command_state_local"
  chmod 0644 "$bootstrap_state_local" "$command_state_local"
  rm -f @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
  printf '%s\n' '{}' > @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json
  printf '%s\n' '{}' > @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
  chmod 0644 @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
  if [ -f "$bootstrap_state_local" ]; then
    cp "$bootstrap_state_local" @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json
  fi
  if [ -f "$command_state_local" ]; then
    cp "$command_state_local" @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
  fi
}

if ! [ -d @WORKSPACE_MOUNT@ ]; then
  echo "workspace mount is unavailable at @WORKSPACE_MOUNT@" >&2
  exit 1
fi

if ! [ -r "$metadata" ]; then
  echo "host cwd metadata is unavailable at $metadata" >&2
  exit 1
fi

log_phase prepare-agent-session-metadata-ready
candidate=$(cat "$metadata")
if [ -z "$candidate" ]; then
  echo "host cwd metadata file is empty: $metadata" >&2
  exit 1
fi
start_dir=$candidate

printf '%s\n' "$start_dir" > @START_DIR_FILE@
chmod 0644 @START_DIR_FILE@

if [ -r "$session_mode_file" ]; then
  session_mode=$(cat "$session_mode_file")
fi

printf '%s\n' "$session_mode" > @AGENT_SESSION_MODE_FILE@
chmod 0644 @AGENT_SESSION_MODE_FILE@

if [ "$session_mode" = "agent-exec" ] || [ "$session_mode" = "agent-attach-exec" ]; then
  log_phase prepare-agent-session-mount-exec-output-start
  mkdir -p @AGENT_EXEC_OUTPUT_MOUNT@
  if ! mountpoint -q @AGENT_EXEC_OUTPUT_MOUNT@; then
    if ! mount -t virtiofs hostexecoutput @AGENT_EXEC_OUTPUT_MOUNT@; then
      echo "failed to mount agent exec output share" >&2
      exit 1
    fi
  fi
  log_phase prepare-agent-session-mount-exec-output-done
  sync_guest_state_files
  printf '%s\n' "prepare-agent-session-mounted-exec-output" > @AGENT_EXEC_OUTPUT_MOUNT@/attach_stage
fi

log_phase prepare-agent-session-state-dir-start
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
log_phase prepare-agent-session-state-dir-done
if [ -r "$session_term_file" ]; then
  cat "$session_term_file" > "$session_term_state_file"
  chmod 0644 "$session_term_state_file"
fi
if [ -r "$session_columns_file" ]; then
  cat "$session_columns_file" > "$session_columns_state_file"
  chmod 0644 "$session_columns_state_file"
fi
if [ -r "$session_lines_file" ]; then
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

if [ "$agent_tools_enabled" = "1" ]; then
  log_phase prepare-agent-session-mount-agent-tools-start
  mkdir -p "$agent_tools_mount"
  if ! mountpoint -q "$agent_tools_mount"; then
    if ! mount -t virtiofs -o exec hostagenttools "$agent_tools_mount"; then
      echo "failed to mount host agent tools share" >&2
      exit 1
    fi
  fi
  log_phase prepare-agent-session-mount-agent-tools-done
fi

if [ "$worker_bridge_enabled" = "1" ]; then
  log_phase prepare-agent-session-mount-worker-bridge-start
  mkdir -p @WORKER_BRIDGE_MOUNT@
  if ! mountpoint -q @WORKER_BRIDGE_MOUNT@; then
    if ! mount -t virtiofs hostworkerbridge @WORKER_BRIDGE_MOUNT@; then
      echo "failed to mount Firebreak worker bridge share" >&2
      exit 1
    fi
  fi
  log_phase prepare-agent-session-mount-worker-bridge-done
fi

if [ -r "$session_command_file" ]; then
  log_phase prepare-agent-session-command-file-start
  cat "$session_command_file" > @AGENT_COMMAND_FILE@
  chmod 0644 @AGENT_COMMAND_FILE@
  sync_guest_state_files
  if [ "$session_mode" = "agent-attach-exec" ]; then
    printf '%s\n' "prepare-agent-session-command-ready" > @AGENT_EXEC_OUTPUT_MOUNT@/attach_stage
  fi
  log_phase prepare-agent-session-command-file-done
fi

if [ "$start_dir" != "@WORKSPACE_MOUNT@" ]; then
  log_phase prepare-agent-session-bind-workspace-start
  if [ -L "$start_dir" ]; then
    rm -f "$start_dir"
  fi

  if ! mountpoint -q "$start_dir"; then
    parent=$(dirname "$start_dir")
    mkdir -p "$parent" "$start_dir"

    if [ -e "$start_dir" ] && ! [ -d "$start_dir" ]; then
      echo "refusing to replace existing non-directory path: $start_dir"
    else
      mount --bind @WORKSPACE_MOUNT@ "$start_dir"
    fi
  fi
  log_phase prepare-agent-session-bind-workspace-done
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
log_phase prepare-agent-session-done
