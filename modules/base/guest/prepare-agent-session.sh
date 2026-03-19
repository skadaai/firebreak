set -eu

metadata=@HOST_META_MOUNT@/mount-path
session_mode=agent
session_command_file=@HOST_META_MOUNT@/agent-command
session_mode_file=@HOST_META_MOUNT@/agent-session-mode
start_dir=@WORKSPACE_MOUNT@

for _ in $(seq 1 50); do
  if [ -d @WORKSPACE_MOUNT@ ] && [ -r "$metadata" ]; then
    break
  fi
  sleep 0.1
done

if [ -d @WORKSPACE_MOUNT@ ] && [ -r "$metadata" ]; then
  candidate=$(cat "$metadata")
  if [ -n "$candidate" ]; then
    start_dir=$candidate
  fi
else
  echo "workspace or host cwd metadata not ready; continuing with the workspace mount only"
fi

printf '%s\n' "$start_dir" > @START_DIR_FILE@
chmod 0644 @START_DIR_FILE@

if [ -r "$session_mode_file" ]; then
  session_mode=$(cat "$session_mode_file")
fi

printf '%s\n' "$session_mode" > @AGENT_SESSION_MODE_FILE@
chmod 0644 @AGENT_SESSION_MODE_FILE@

if [ "$session_mode" = "agent-exec" ]; then
  mkdir -p @AGENT_EXEC_OUTPUT_MOUNT@
  if ! mountpoint -q @AGENT_EXEC_OUTPUT_MOUNT@; then
    if ! mount -t virtiofs hostexecoutput @AGENT_EXEC_OUTPUT_MOUNT@; then
      echo "failed to mount agent exec output share" >&2
      exit 1
    fi
  fi
fi

if [ -r "$session_command_file" ]; then
  cat "$session_command_file" > @AGENT_COMMAND_FILE@
  chmod 0644 @AGENT_COMMAND_FILE@
fi

if [ "$start_dir" != "@WORKSPACE_MOUNT@" ]; then
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
fi

if [ "@AGENT_CONFIG_ENABLED@" != "1" ]; then
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
    ;;
  workspace)
    resolved_dir=$start_dir/@AGENT_CONFIG_DIR_NAME@
    ;;
  vm)
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
  fresh)
    resolved_dir=@AGENT_CONFIG_FRESH_DIR@
    rm -rf "$resolved_dir"
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
  *)
    echo "unsupported agent config mode '$mode'; falling back to vm" >&2
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
esac

printf '%s\n' "$resolved_dir" > @AGENT_CONFIG_DIR_FILE@
chmod 0644 @AGENT_CONFIG_DIR_FILE@
