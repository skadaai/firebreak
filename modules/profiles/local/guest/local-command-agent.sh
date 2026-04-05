#!/usr/bin/env bash
set -eu

@FIREBREAK_AGENT_COMMAND_REQUEST_LIB@
@FIREBREAK_AGENT_COMMAND_STATE_LIB@

command_shell_init_file=@COMMAND_SHELL_INIT_FILE@
command_agent_ready_file=@AGENT_EXEC_OUTPUT_MOUNT@/command-agent-ready
command_agent_last_request_file=$guest_state_dir/command-agent-last-request-id
stdout_path=@AGENT_EXEC_OUTPUT_MOUNT@/stdout
stderr_path=@AGENT_EXEC_OUTPUT_MOUNT@/stderr
exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code

mkdir -p "$guest_state_dir"

if ! [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
  echo "agent exec output share is unavailable at @AGENT_EXEC_OUTPUT_MOUNT@" >&2
  exit 1
fi

if ! [ -r "$command_shell_init_file" ]; then
  command_shell_init_file=""
fi

last_request_id=""
if [ -r "$command_agent_last_request_file" ]; then
  last_request_id=$(cat "$command_agent_last_request_file")
fi

printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$command_agent_ready_file"
chmod 0644 "$command_agent_ready_file"

reject_request() {
  request_status=$1
  request_detail=$2
  rm -f "$stdout_path" "$stderr_path" "$exit_code_path"
  printf '%s\n' "$request_detail" >"$stderr_path"
  write_command_state command-rejected error "$request_detail" "$request_status"
  printf '%s\n' "$request_status" >"$exit_code_path"
}

while :; do
  command_request_loaded=0
  if ! [ -r "$command_request_file" ]; then
    sleep 0.2
    continue
  fi

  if ! ensure_command_request_loaded; then
    sleep 0.2
    continue
  fi

  if [ -z "${command_request_id:-}" ] || [ "$command_request_id" = "$last_request_id" ]; then
    sleep 0.2
    continue
  fi

  if [ "$command_request_session_mode" != "agent-exec" ]; then
    reject_request 1 "local command-agent supports only agent-exec requests"
    last_request_id=$command_request_id
    printf '%s\n' "$last_request_id" > "$command_agent_last_request_file"
    chmod 0644 "$command_agent_last_request_file"
    continue
  fi

  FIREBREAK_AGENT_POWER_ACTION=stay-alive @RUN_AGENT_EXEC_SCRIPT@
  last_request_id=$command_request_id
  printf '%s\n' "$last_request_id" > "$command_agent_last_request_file"
  chmod 0644 "$command_agent_last_request_file"
done
