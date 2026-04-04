set -eu

start_dir=@WORKSPACE_MOUNT@
prompt_source=@HOST_META_MOUNT@/prompt
session_mode=agent-exec

if ! [ -d @WORKSPACE_MOUNT@ ]; then
  echo "workspace mount is missing: @WORKSPACE_MOUNT@" >&2
  exit 1
fi

printf '%s\n' "$start_dir" > @START_DIR_FILE@
chmod 0644 @START_DIR_FILE@

printf '%s\n' "$session_mode" > @AGENT_SESSION_MODE_FILE@
chmod 0644 @AGENT_SESSION_MODE_FILE@

mkdir -p @AGENT_EXEC_OUTPUT_MOUNT@
if ! mountpoint -q @AGENT_EXEC_OUTPUT_MOUNT@; then
  if ! mount -t virtiofs hostexecoutput @AGENT_EXEC_OUTPUT_MOUNT@; then
    echo "failed to mount agent exec output share" >&2
    exit 1
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

if ! [ -r "$prompt_source" ]; then
  echo "required prompt input is missing: $prompt_source" >&2
  exit 1
fi

@CAT@ "$prompt_source" > @AGENT_PROMPT_FILE@
chmod 0644 @AGENT_PROMPT_FILE@

if [ "@AGENT_CONFIG_ENABLED@" = "1" ]; then
  resolved_dir=@AGENT_CONFIG_VM_DIR@

  if mountpoint -q @SHARED_AGENT_CONFIG_HOST_MOUNT@; then
    resolved_dir=@SHARED_AGENT_CONFIG_HOST_MOUNT@/@AGENT_CONFIG_SUBDIR@
    @RUNUSER@ -u @DEV_USER@ -- mkdir -p "$resolved_dir"
  else
    mkdir -p "$resolved_dir"
    @CHOWN@ @DEV_USER@:@DEV_USER@ "$resolved_dir"
  fi

  printf '%s\n' "$resolved_dir" > @AGENT_CONFIG_DIR_FILE@
  chmod 0644 @AGENT_CONFIG_DIR_FILE@
fi
