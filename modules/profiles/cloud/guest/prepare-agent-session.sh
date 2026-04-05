set -eu

export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT=@SHARED_STATE_ROOT_HOST_MOUNT@
export FIREBREAK_SHARED_STATE_ROOT_VM_ROOT=@SHARED_STATE_ROOT_VM_ROOT@
export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG=@SHARED_STATE_ROOT_MOUNTED_FLAG@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_HOST_MOUNT=@SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@
export FIREBREAK_SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG=@SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@

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

if ! [ -r "$prompt_source" ]; then
  echo "required prompt input is missing: $prompt_source" >&2
  exit 1
fi

@CAT@ "$prompt_source" > @AGENT_PROMPT_FILE@
chmod 0644 @AGENT_PROMPT_FILE@
