set -eu

target=@WORKSPACE_MOUNT@
session_mode=shell
agent_command=@AGENT_COMMAND@
if [ -r @START_DIR_FILE@ ]; then
  target=$(cat @START_DIR_FILE@)
fi

if [ -r @AGENT_SESSION_MODE_FILE@ ]; then
  session_mode=$(cat @AGENT_SESSION_MODE_FILE@)
fi

if [ -r @AGENT_COMMAND_FILE@ ]; then
  agent_command=$(cat @AGENT_COMMAND_FILE@)
fi

if [ ! -d "$target" ]; then
  target=@WORKSPACE_MOUNT@
fi

cd "$target"

printf '\n\e[0m\e[1mWelcome to %s - %s\e[0m\n' "@BRANDING_NAME@" "@BRANDING_TAGLINE@"
printf '[ vm: %s | mode: %s | workspace: %s ]\n' "@AGENT_VM_NAME@" "$session_mode" "$target"

case "$session_mode" in
  shell)
    @BASH@ -i || true
    exit 0
    ;;
  agent)
    if [ -n "$agent_command" ]; then
      exec @BASH@ -ic "$agent_command; exec @BASH@ -i"
    fi
    exec @BASH@ -i
    ;;
  agent-exec)
    if [ -n "$agent_command" ]; then
      exec env FIREBREAK_AGENT_COMMAND="$agent_command" @BASH@ -ic '
        status=0
        stdout_path=@AGENT_EXEC_OUTPUT_MOUNT@/stdout
        stderr_path=@AGENT_EXEC_OUTPUT_MOUNT@/stderr
        exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code
        rm -f "$stdout_path" "$stderr_path" "$exit_code_path"
        eval "$FIREBREAK_AGENT_COMMAND" >"$stdout_path" 2>"$stderr_path" || status=$?
        printf "%s\n" "$status" >"$exit_code_path"
        sudo poweroff >/dev/null 2>&1 || true
        exit "$status"
      '
    fi
    exec @BASH@ -i
    ;;
  *)
    printf 'unknown agent session mode: %s\n' "$session_mode" >&2
    exec @BASH@ -i
    ;;
esac
