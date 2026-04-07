#!/usr/bin/env bash
set -eu

@FIREBREAK_AGENT_COMMAND_REQUEST_LIB@
@FIREBREAK_AGENT_COMMAND_STATE_LIB@
@FIREBREAK_PROFILE_LIB@

command_shell_init_file=@COMMAND_SHELL_INIT_FILE@
power_action=${FIREBREAK_AGENT_POWER_ACTION:-poweroff}
bootstrap_wait_enabled=@COLD_EXEC_BOOTSTRAP_WAIT_ENABLED@

if ! [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
  echo "agent exec output share is unavailable at @AGENT_EXEC_OUTPUT_MOUNT@" >&2
  exit 1
fi

ensure_command_request_loaded
FIREBREAK_AGENT_COMMAND=${command_request_command:-}
export FIREBREAK_AGENT_COMMAND

if [ -z "$FIREBREAK_AGENT_COMMAND" ]; then
  echo "command request did not provide a command for firebreak-run-agent-exec" >&2
  exit 1
fi

if [ "$command_request_session_mode" != "agent-exec" ]; then
  echo "firebreak-run-agent-exec requires an agent-exec request, got: $command_request_session_mode" >&2
  exit 1
fi

target_dir=${command_request_start_dir:-@WORKSPACE_MOUNT@}
if ! [ -d "$target_dir" ]; then
  target_dir=@WORKSPACE_MOUNT@
fi
cd "$target_dir"

if ! [ -r "$command_shell_init_file" ]; then
  command_shell_init_file=""
fi

status=0
stdout_path=@AGENT_EXEC_OUTPUT_MOUNT@/stdout
stderr_path=@AGENT_EXEC_OUTPUT_MOUNT@/stderr
exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code
systemd_time_path=@AGENT_EXEC_OUTPUT_MOUNT@/systemd-time.txt
systemd_blame_path=@AGENT_EXEC_OUTPUT_MOUNT@/systemd-blame.txt
systemd_basic_chain_path=@AGENT_EXEC_OUTPUT_MOUNT@/systemd-basic-target-chain.txt
systemd_command_chain_path=@AGENT_EXEC_OUTPUT_MOUNT@/systemd-cold-command-chain.txt
rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

capture_systemd_boot_profile() {
  if [ "${command_request_capture_systemd_profile:-0}" != "1" ]; then
    return 0
  fi

  if ! command -v systemd-analyze >/dev/null 2>&1; then
    return 0
  fi

  firebreak_profile_guest_mark run-agent-exec systemd-profile-start
  systemd-analyze time --no-pager >"$systemd_time_path" 2>/dev/null || true
  systemd-analyze blame --no-pager >"$systemd_blame_path" 2>/dev/null || true
  systemd-analyze critical-chain basic.target --no-pager >"$systemd_basic_chain_path" 2>/dev/null || true
  systemd-analyze critical-chain cold-command-exec.service --no-pager >"$systemd_command_chain_path" 2>/dev/null || true
  firebreak_profile_guest_mark run-agent-exec systemd-profile-done
}

if [ "$bootstrap_wait_enabled" = "1" ] && command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
  firebreak_profile_guest_mark run-agent-exec bootstrap-wait-start
  write_command_state bootstrap-wait running agent-exec 0
  if firebreak-bootstrap-wait; then
    firebreak_profile_guest_mark run-agent-exec bootstrap-wait-done
    :
  else
    status=$?
    firebreak_profile_guest_mark run-agent-exec bootstrap-wait-error "$status"
    write_command_state bootstrap-wait error agent-exec "$status"
    printf "%s\n" "$status" >"$exit_code_path"
    if [ "$power_action" = "poweroff" ]; then
      systemctl poweroff >/dev/null 2>&1 || true
    fi
    exit "$status"
  fi
fi

if [ -n "$command_shell_init_file" ]; then
  # shellcheck disable=SC1090
  . "$command_shell_init_file"
fi

capture_systemd_boot_profile
firebreak_profile_guest_mark run-agent-exec command-start "$FIREBREAK_AGENT_COMMAND"
write_command_state command-start running agent-exec 0
eval "$FIREBREAK_AGENT_COMMAND" >"$stdout_path" 2>"$stderr_path" || status=$?
write_command_state command-exit completed agent-exec "$status"
firebreak_profile_guest_mark run-agent-exec command-exit "$status"
printf "%s\n" "$status" >"$exit_code_path"
if [ "$power_action" = "poweroff" ]; then
  systemctl poweroff >/dev/null 2>&1 || true
fi
exit "$status"
