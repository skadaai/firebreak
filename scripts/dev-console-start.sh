set -eu

target=@WORKSPACE_MOUNT@
session_mode=shell
if [ -r @START_DIR_FILE@ ]; then
  target=$(cat @START_DIR_FILE@)
fi

if [ -r @AGENT_SESSION_MODE_FILE@ ]; then
  session_mode=$(cat @AGENT_SESSION_MODE_FILE@)
fi

if [ ! -d "$target" ]; then
  target=@WORKSPACE_MOUNT@
fi

cd "$target"

case "$session_mode" in
  shell)
    exec @BASH@ -i
    ;;
  agent)
    if [ -n "@AGENT_COMMAND@" ]; then
      printf '%s\n' "__AGENT_ENTRY__@AGENT_COMMAND@"
      exec @BASH@ -ic '@AGENT_COMMAND@; exec @BASH@ -i'
    fi
    exec @BASH@ -i
    ;;
  *)
    printf 'unknown agent session mode: %s\n' "$session_mode" >&2
    exec @BASH@ -i
    ;;
esac
