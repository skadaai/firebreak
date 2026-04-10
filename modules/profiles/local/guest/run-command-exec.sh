#!/usr/bin/env bash
set -eu

@FIREBREAK_WORKER_COMMAND_REQUEST_LIB@
@FIREBREAK_WORKER_COMMAND_STATE_LIB@
@FIREBREAK_PROFILE_LIB@

command_shell_init_file=@COMMAND_SHELL_INIT_FILE@
power_action=${FIREBREAK_COMMAND_POWER_ACTION:-poweroff}
bootstrap_wait_enabled=@COLD_EXEC_BOOTSTRAP_WAIT_ENABLED@

if [ "$(@ID@ -u)" = "0" ]; then
  firebreak_profile_guest_mark run-command-exec privilege-drop-start @DEV_USER@
  target_uid=$(@ID@ -u @DEV_USER@)
  target_gid=$(@ID@ -g @DEV_USER@)
  exec env \
    FIREBREAK_COMMAND_PRIV_DROP_DONE=1 \
    USER=@DEV_USER@ \
    LOGNAME=@DEV_USER@ \
    HOME=@DEV_HOME@ \
    SHELL=@BASH@ \
    @SETPRIV@ \
      --reuid "$target_uid" \
      --regid "$target_gid" \
      --init-groups \
      "$0"
fi

if [ "${FIREBREAK_COMMAND_PRIV_DROP_DONE:-0}" = "1" ] && [ "$(@ID@ -u)" = "0" ]; then
  echo "failed to drop privileges for firebreak-run-command-exec" >&2
  exit 1
fi

if ! [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
  echo "command output share is unavailable at @COMMAND_OUTPUT_MOUNT@" >&2
  exit 1
fi

ensure_command_request_loaded
FIREBREAK_TOOL_COMMAND=${command_request_command:-}
export FIREBREAK_TOOL_COMMAND

if [ -z "$FIREBREAK_TOOL_COMMAND" ]; then
  echo "command request did not provide a command for firebreak-run-command-exec" >&2
  exit 1
fi

if [ "$command_request_session_mode" != "command-exec" ]; then
  echo "firebreak-run-command-exec requires an command-exec request, got: $command_request_session_mode" >&2
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
stdout_path=@COMMAND_OUTPUT_MOUNT@/stdout
stderr_path=@COMMAND_OUTPUT_MOUNT@/stderr
exit_code_path=@COMMAND_OUTPUT_MOUNT@/exit_code
systemd_time_path=@COMMAND_OUTPUT_MOUNT@/systemd-time.txt
systemd_blame_path=@COMMAND_OUTPUT_MOUNT@/systemd-blame.txt
systemd_basic_chain_path=@COMMAND_OUTPUT_MOUNT@/systemd-basic-target-chain.txt
systemd_command_chain_path=@COMMAND_OUTPUT_MOUNT@/systemd-cold-command-chain.txt
rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

capture_systemd_boot_profile() {
  if [ "${command_request_capture_systemd_profile:-0}" != "1" ]; then
    return 0
  fi

  if ! command -v systemd-analyze >/dev/null 2>&1; then
    return 0
  fi

  firebreak_profile_guest_mark run-command-exec systemd-profile-start
  systemd-analyze time --no-pager >"$systemd_time_path" 2>/dev/null || true
  systemd-analyze blame --no-pager >"$systemd_blame_path" 2>/dev/null || true
  systemd-analyze critical-chain basic.target --no-pager >"$systemd_basic_chain_path" 2>/dev/null || true
  systemd-analyze critical-chain cold-command-exec.service --no-pager >"$systemd_command_chain_path" 2>/dev/null || true
  firebreak_profile_guest_mark run-command-exec systemd-profile-done
}

if [ "$bootstrap_wait_enabled" = "1" ] && command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
  firebreak_profile_guest_mark run-command-exec bootstrap-wait-start
  write_command_state bootstrap-wait running command-exec 0
  if ! firebreak-bootstrap-wait; then
    status=$?
    firebreak_profile_guest_mark run-command-exec bootstrap-wait-error "$status"
    write_command_state bootstrap-wait error command-exec "$status"
    printf "%s\n" "$status" >"$exit_code_path"
    if [ "$power_action" = "poweroff" ]; then
      systemctl poweroff >/dev/null 2>&1 || true
    fi
    exit "$status"
  fi
  firebreak_profile_guest_mark run-command-exec bootstrap-wait-done
fi

if [ -n "$command_shell_init_file" ]; then
  # shellcheck disable=SC1090
  . "$command_shell_init_file"
fi

capture_systemd_boot_profile
firebreak_profile_guest_mark run-command-exec command-start "$FIREBREAK_TOOL_COMMAND"
write_command_state command-start running command-exec 0
eval "$FIREBREAK_TOOL_COMMAND" >"$stdout_path" 2>"$stderr_path" || status=$?
write_command_state command-exit completed command-exec "$status"
firebreak_profile_guest_mark run-command-exec command-exit "$status"
printf "%s\n" "$status" >"$exit_code_path"
if [ "$power_action" = "poweroff" ]; then
  systemctl poweroff >/dev/null 2>&1 || true
fi
exit "$status"
