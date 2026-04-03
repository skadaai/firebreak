set -eu

metadata=@HOST_META_MOUNT@/mount-path
session_mode=agent
session_command_file=@HOST_META_MOUNT@/agent-command
session_mode_file=@HOST_META_MOUNT@/agent-session-mode
session_term_file=@HOST_META_MOUNT@/agent-term
session_columns_file=@HOST_META_MOUNT@/agent-columns
session_lines_file=@HOST_META_MOUNT@/agent-lines
worker_mode_file=@HOST_META_MOUNT@/worker-mode
worker_modes_file=@HOST_META_MOUNT@/worker-modes
worker_proxy_mode_file=@HOST_META_MOUNT@/worker-proxy-mode
agent_tools_enabled=@AGENT_TOOLS_ENABLED@
agent_tools_mount=@AGENT_TOOLS_MOUNT@
start_dir=@WORKSPACE_MOUNT@
worker_bridge_enabled=@WORKER_BRIDGE_ENABLED@
guest_state_dir=/run/firebreak-agent
bootstrap_state_local=$guest_state_dir/bootstrap-state.json
command_state_local=$guest_state_dir/command-state.json
session_term_state_file=$guest_state_dir/session-term
session_columns_state_file=$guest_state_dir/session-columns
session_lines_state_file=$guest_state_dir/session-lines
worker_mode_state_file=$guest_state_dir/worker-mode
worker_modes_state_file=$guest_state_dir/worker-modes
worker_proxy_mode_state_file=$guest_state_dir/worker-proxy-mode

log_phase() {
  phase=$1
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s %s\n' "[firebreak-session]" "$timestamp $phase"
}

sync_guest_state_files() {
  if ! [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
    return 0
  fi
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

metadata_ready=0
for _ in $(seq 1 50); do
  if [ -d @WORKSPACE_MOUNT@ ] && [ -r "$metadata" ]; then
    metadata_ready=1
    break
  fi
  sleep 0.1
done

if [ "$metadata_ready" = "1" ] && [ -d @WORKSPACE_MOUNT@ ] && [ -r "$metadata" ]; then
  log_phase prepare-agent-session-metadata-ready
  candidate=$(cat "$metadata")
  if [ -n "$candidate" ]; then
    start_dir=$candidate
  fi
else
  log_phase prepare-agent-session-metadata-fallback
  echo "workspace or host cwd metadata not ready; continuing with the workspace mount only"
fi

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
rm -f \
  "$session_term_state_file" \
  "$session_columns_state_file" \
  "$session_lines_state_file" \
  "$worker_mode_state_file" \
  "$worker_modes_state_file" \
  "$worker_proxy_mode_state_file"
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
if [ -r "$worker_proxy_mode_file" ]; then
  cat "$worker_proxy_mode_file" > "$worker_proxy_mode_state_file"
  chmod 0644 "$worker_proxy_mode_state_file"
fi

if [ "$agent_tools_enabled" = "1" ]; then
  log_phase prepare-agent-session-mount-agent-tools-start
  mkdir -p "$agent_tools_mount"
  if ! mountpoint -q "$agent_tools_mount"; then
    if ! mount -t virtiofs hostagenttools "$agent_tools_mount"; then
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

if [ "@AGENT_CONFIG_ENABLED@" != "1" ]; then
  log_phase prepare-agent-session-done
  exit 0
fi

mode=vm
mode_file=@HOST_META_MOUNT@/agent-config-mode
resolved_dir=@AGENT_CONFIG_VM_DIR@

if [ -r "$mode_file" ]; then
  mode=$(cat "$mode_file")
fi

case "$mode" in
  host)
    log_phase prepare-agent-session-agent-config-host-start
    mkdir -p @AGENT_CONFIG_HOST_MOUNT@
    if ! mountpoint -q @AGENT_CONFIG_HOST_MOUNT@; then
      if ! mount -t virtiofs hostagentconfig @AGENT_CONFIG_HOST_MOUNT@; then
        echo "failed to mount host agent config share; falling back to vm config" >&2
        mode=vm
      fi
    fi

    if [ "$mode" = "host" ]; then
      resolved_dir=@AGENT_CONFIG_HOST_MOUNT@
    fi
    log_phase prepare-agent-session-agent-config-host-done
    ;;
  workspace)
    log_phase prepare-agent-session-agent-config-workspace-start
    resolved_dir=$start_dir/@AGENT_CONFIG_DIR_NAME@
    if ! [ -d "$resolved_dir" ]; then
      if [ -L "$resolved_dir" ]; then
        link_target=$(readlink "$resolved_dir")
        case "$link_target" in
          /*)
            resolved_target=$link_target
            ;;
          *)
            resolved_target=$(dirname "$resolved_dir")/$link_target
            ;;
        esac
        @RUNUSER@ -u @DEV_USER@ -- @MKDIR@ -p "$resolved_target"
      elif [ -e "$resolved_dir" ]; then
        echo "workspace agent config path exists but is not a directory: $resolved_dir" >&2
        exit 1
      else
        @RUNUSER@ -u @DEV_USER@ -- @MKDIR@ -p "$resolved_dir"
      fi
    fi
    log_phase prepare-agent-session-agent-config-workspace-done
    ;;
  vm)
    log_phase prepare-agent-session-agent-config-vm-start
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    log_phase prepare-agent-session-agent-config-vm-done
    ;;
  fresh)
    log_phase prepare-agent-session-agent-config-fresh-start
    resolved_dir=@AGENT_CONFIG_FRESH_DIR@
    rm -rf "$resolved_dir"
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    log_phase prepare-agent-session-agent-config-fresh-done
    ;;
  *)
    log_phase prepare-agent-session-agent-config-fallback-start
    echo "unsupported agent config mode '$mode'; falling back to vm" >&2
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    log_phase prepare-agent-session-agent-config-fallback-done
    ;;
esac

printf '%s\n' "$resolved_dir" > @AGENT_CONFIG_DIR_FILE@
chmod 0644 @AGENT_CONFIG_DIR_FILE@
log_phase prepare-agent-session-done
