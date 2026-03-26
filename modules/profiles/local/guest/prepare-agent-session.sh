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

if [ "@SHARED_AGENT_CONFIG_ENABLED@" = "1" ]; then
  mkdir -p @SHARED_AGENT_CONFIG_HOST_MOUNT@ @SHARED_AGENT_CONFIG_FRESH_ROOT@
  chown @DEV_USER@:@DEV_USER@ @SHARED_AGENT_CONFIG_FRESH_ROOT@
  rm -f @SHARED_AGENT_CONFIG_MOUNTED_FLAG@

  if mountpoint -q @SHARED_AGENT_CONFIG_HOST_MOUNT@; then
    touch @SHARED_AGENT_CONFIG_MOUNTED_FLAG@
  elif mount_output=$(mount -t virtiofs hostagentconfigroot @SHARED_AGENT_CONFIG_HOST_MOUNT@ 2>&1); then
    touch @SHARED_AGENT_CONFIG_MOUNTED_FLAG@
  else
    printf '%s\n' "Firebreak shared agent config root is not available; continuing without host-backed config: $mount_output"
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
    if ! [ -e @SHARED_AGENT_CONFIG_MOUNTED_FLAG@ ]; then
      echo "failed to mount host agent config share; falling back to vm config" >&2
      mode=vm
    else
      resolved_dir=@SHARED_AGENT_CONFIG_HOST_MOUNT@/@AGENT_CONFIG_SUBDIR@
      @RUNUSER@ -u @DEV_USER@ -- @MKDIR@ -p "$resolved_dir"
    fi
    ;;
  workspace)
    resolved_dir=$start_dir/@AGENT_CONFIG_DIR_NAME@
    if ! [ -d "$resolved_dir" ]; then
      if [ -L "$resolved_dir" ]; then
        link_target=$(readlink "$resolved_dir")
        case "$link_target" in
          /*)
            if [ -e @SHARED_AGENT_CONFIG_MOUNTED_FLAG@ ]; then
              resolved_dir=@SHARED_AGENT_CONFIG_HOST_MOUNT@/@AGENT_CONFIG_SUBDIR@
              @RUNUSER@ -u @DEV_USER@ -- @MKDIR@ -p "$resolved_dir"
            else
              echo "host-backed config share is unavailable for external workspace config path: $resolved_dir" >&2
              exit 1
            fi
            ;;
          *)
            resolved_target=$(dirname "$resolved_dir")/$link_target
            @RUNUSER@ -u @DEV_USER@ -- @MKDIR@ -p "$resolved_target"
            ;;
        esac
      elif [ -e "$resolved_dir" ]; then
        echo "workspace agent config path exists but is not a directory: $resolved_dir" >&2
        exit 1
      else
        @RUNUSER@ -u @DEV_USER@ -- @MKDIR@ -p "$resolved_dir"
      fi
    fi
    ;;
  vm)
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
  fresh)
    resolved_dir=@SHARED_AGENT_CONFIG_FRESH_ROOT@/@AGENT_CONFIG_SUBDIR@
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
