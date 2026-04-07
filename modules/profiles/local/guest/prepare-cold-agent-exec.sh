set -eu

@FIREBREAK_AGENT_COMMAND_REQUEST_LIB@
@FIREBREAK_PROFILE_LIB@

agent_tools_enabled=@AGENT_TOOLS_ENABLED@
agent_tools_mount=@AGENT_TOOLS_MOUNT@
start_dir=@WORKSPACE_MOUNT@
guest_state_dir=/run/firebreak-worker
bootstrap_state_local=$guest_state_dir/bootstrap-state.json
command_state_local=$guest_state_dir/command-state.json

export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT=@SHARED_STATE_ROOT_HOST_MOUNT@
export FIREBREAK_SHARED_STATE_ROOT_VM_ROOT=@SHARED_STATE_ROOT_VM_ROOT@
export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG=@SHARED_STATE_ROOT_MOUNTED_FLAG@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_HOST_MOUNT=@SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG=@SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@

log_phase() {
  phase=$1
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s %s\n' "[firebreak-session]" "$timestamp $phase"
  firebreak_profile_guest_mark prepare-cold-agent-exec "$phase"
}

sync_guest_state_files() {
  mkdir -p "$guest_state_dir"
  printf '%s\n' '{}' > "$bootstrap_state_local"
  printf '%s\n' '{}' > "$command_state_local"
  chmod 0644 "$bootstrap_state_local" "$command_state_local"
  @CHOWN@ @DEV_USER@:@DEV_USER@ "$guest_state_dir" "$bootstrap_state_local" "$command_state_local"
  rm -f @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
  cp "$bootstrap_state_local" @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json
  cp "$command_state_local" @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
  chmod 0644 @AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json @AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
}

sync_guest_session_request_files() {
  printf '%s\n' "$command_request_session_mode" > @AGENT_SESSION_MODE_FILE@
  chmod 0644 @AGENT_SESSION_MODE_FILE@

  if [ -n "$command_request_command" ]; then
    printf '%s\n' "$command_request_command" > @AGENT_COMMAND_FILE@
    chmod 0644 @AGENT_COMMAND_FILE@
  else
    rm -f @AGENT_COMMAND_FILE@
  fi

  printf '%s\n' "$start_dir" > @START_DIR_FILE@
  chmod 0644 @START_DIR_FILE@
}

if ! [ -d @WORKSPACE_MOUNT@ ]; then
  echo "workspace mount is unavailable at @WORKSPACE_MOUNT@" >&2
  exit 1
fi

if ! [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
  echo "agent exec output share is unavailable at @AGENT_EXEC_OUTPUT_MOUNT@" >&2
  exit 1
fi

ensure_command_request_loaded

if [ "$command_request_session_mode" != "agent-exec" ]; then
  echo "prepare-cold-agent-exec requires an agent-exec request, got: $command_request_session_mode" >&2
  exit 1
fi

if [ -n "$command_request_start_dir" ]; then
  start_dir=$command_request_start_dir
fi

log_phase prepare-cold-agent-exec-start
log_phase prepare-cold-agent-exec-adopt-host-identity-start
@ADOPT_HOST_IDENTITY_SCRIPT@
log_phase prepare-cold-agent-exec-adopt-host-identity-done
sync_guest_state_files
sync_guest_session_request_files

if [ "$start_dir" != "@WORKSPACE_MOUNT@" ]; then
  log_phase prepare-cold-agent-exec-bind-workspace-start
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
  log_phase prepare-cold-agent-exec-bind-workspace-done
fi

if [ "$agent_tools_enabled" = "1" ]; then
  log_phase prepare-cold-agent-exec-mount-agent-tools-start
  mkdir -p "$agent_tools_mount"
  if ! mountpoint -q "$agent_tools_mount"; then
    if ! mount -t virtiofs -o exec hostagenttools "$agent_tools_mount"; then
      echo "failed to mount host agent tools share" >&2
      exit 1
    fi
  fi
  log_phase prepare-cold-agent-exec-mount-agent-tools-done
fi

if [ "@SHARED_STATE_ROOT_ENABLED@" = "1" ]; then
  mkdir -p @SHARED_STATE_ROOT_HOST_MOUNT@ @SHARED_STATE_ROOT_FRESH_ROOT@
  @CHOWN@ @DEV_USER@:@DEV_USER@ @SHARED_STATE_ROOT_FRESH_ROOT@
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

log_phase prepare-cold-agent-exec-done
