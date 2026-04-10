#!/usr/bin/env bash
set -eu

@FIREBREAK_WORKER_COMMAND_REQUEST_LIB@
@FIREBREAK_WORKER_COMMAND_STATE_LIB@

command_shell_init_file=@COMMAND_SHELL_INIT_FILE@
command_service_ready_file=@COMMAND_OUTPUT_MOUNT@/command-service-ready
command_service_last_request_file=$guest_state_dir/command-service-last-request-id
stdout_path=@COMMAND_OUTPUT_MOUNT@/stdout
stderr_path=@COMMAND_OUTPUT_MOUNT@/stderr
exit_code_path=@COMMAND_OUTPUT_MOUNT@/exit_code

mkdir -p "$guest_state_dir"

if ! [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
  echo "command output share is unavailable at @COMMAND_OUTPUT_MOUNT@" >&2
  exit 1
fi

if ! [ -r "$command_shell_init_file" ]; then
  command_shell_init_file=""
fi

last_request_id=""
if [ -r "$command_service_last_request_file" ]; then
  last_request_id=$(cat "$command_service_last_request_file")
fi

printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$command_service_ready_file"
chmod 0644 "$command_service_ready_file"

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

  if [ "$command_request_session_mode" != "command-exec" ]; then
    reject_request 1 "local command worker supports only command-exec requests"
    last_request_id=$command_request_id
    printf '%s\n' "$last_request_id" > "$command_service_last_request_file"
    chmod 0644 "$command_service_last_request_file"
    continue
  fi

  last_request_id=$command_request_id
  printf '%s\n' "$last_request_id" > "$command_service_last_request_file"
  chmod 0644 "$command_service_last_request_file"
  FIREBREAK_COMMAND_POWER_ACTION=stay-alive @RUN_COMMAND_EXEC_SCRIPT@
done
