#!/usr/bin/env bash
set -eu

@FIREBREAK_AGENT_COMMAND_STATE_LIB@

command_shell_init_file=@COMMAND_SHELL_INIT_FILE@

if ! [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
  echo "agent exec output share is unavailable at @AGENT_EXEC_OUTPUT_MOUNT@" >&2
  exit 1
fi

if [ -z "${FIREBREAK_AGENT_COMMAND:-}" ]; then
  echo "FIREBREAK_AGENT_COMMAND is required for firebreak-run-agent-exec" >&2
  exit 1
fi

if ! [ -r "$command_shell_init_file" ]; then
  command_shell_init_file=""
fi

status=0
stdout_path=@AGENT_EXEC_OUTPUT_MOUNT@/stdout
stderr_path=@AGENT_EXEC_OUTPUT_MOUNT@/stderr
exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code
rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

if command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
  write_command_state bootstrap-wait running agent-exec 0
  if firebreak-bootstrap-wait; then
    :
  else
    status=$?
    write_command_state bootstrap-wait error agent-exec "$status"
    printf "%s\n" "$status" >"$exit_code_path"
    sudo poweroff >/dev/null 2>&1 || true
    exit "$status"
  fi
fi

if [ -n "$command_shell_init_file" ]; then
  # shellcheck disable=SC1090
  . "$command_shell_init_file"
fi

write_command_state command-start running agent-exec 0
eval "$FIREBREAK_AGENT_COMMAND" >"$stdout_path" 2>"$stderr_path" || status=$?
write_command_state command-exit completed agent-exec "$status"
printf "%s\n" "$status" >"$exit_code_path"
sudo poweroff >/dev/null 2>&1 || true
exit "$status"
