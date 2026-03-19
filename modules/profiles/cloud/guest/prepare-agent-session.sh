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

if ! [ -r "$prompt_source" ]; then
  echo "required prompt input is missing: $prompt_source" >&2
  exit 1
fi

@CAT@ "$prompt_source" > @AGENT_PROMPT_FILE@
chmod 0644 @AGENT_PROMPT_FILE@

if [ "@AGENT_CONFIG_ENABLED@" != "1" ]; then
  exit 0
fi

resolved_dir=@AGENT_CONFIG_VM_DIR@

mkdir -p @AGENT_CONFIG_HOST_MOUNT@
if ! mountpoint -q @AGENT_CONFIG_HOST_MOUNT@; then
  mount -t virtiofs hostagentconfig @AGENT_CONFIG_HOST_MOUNT@ >/dev/null 2>&1 || true
fi

if mountpoint -q @AGENT_CONFIG_HOST_MOUNT@; then
  resolved_dir=@AGENT_CONFIG_HOST_MOUNT@
else
  mkdir -p "$resolved_dir"
  @CHOWN@ @DEV_USER@:@DEV_USER@ "$resolved_dir"
fi

printf '%s\n' "$resolved_dir" > @AGENT_CONFIG_DIR_FILE@
chmod 0644 @AGENT_CONFIG_DIR_FILE@
