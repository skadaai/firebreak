#!/usr/bin/env bash
set -eu

if [ -n "${PATH:-}" ]; then
  export PATH="/run/current-system/sw/bin:$PATH"
else
  export PATH="/run/current-system/sw/bin"
fi

@FIREBREAK_WORKER_COMMAND_REQUEST_LIB@
@FIREBREAK_WORKER_COMMAND_STATE_LIB@

target=@WORKSPACE_MOUNT@
session_mode=shell
resolved_session_mode=$session_mode
tool_command=@TOOL_COMMAND@
command_process_local=$guest_state_dir/command-processes.txt
command_process_shared=@COMMAND_OUTPUT_MOUNT@/command-processes.txt
command_tty_local=$guest_state_dir/command-tty.txt
command_tty_shared=@COMMAND_OUTPUT_MOUNT@/command-tty.txt
command_job_info_local=$guest_state_dir/command-job.env
command_foreground_helper_local=$guest_state_dir/command-foreground.py
command_signal_stream_shared=@COMMAND_OUTPUT_MOUNT@/command-signals.stream
session_term_state_file=$guest_state_dir/session-term
session_columns_state_file=$guest_state_dir/session-columns
session_lines_state_file=$guest_state_dir/session-lines
command_shell_init_file=@COMMAND_SHELL_INIT_FILE@
attach_shell_flag=-ic
attach_shell_flag=-lc

if [ -r @START_DIR_FILE@ ]; then
  target=$(cat @START_DIR_FILE@)
fi

if [ -r @SESSION_MODE_FILE@ ]; then
  session_mode=$(cat @SESSION_MODE_FILE@)
fi

if [ -r @COMMAND_FILE@ ]; then
  tool_command=$(cat @COMMAND_FILE@)
fi

case "$session_mode" in
  command-exec|command-attach-exec)
    ensure_command_request_loaded
    resolved_session_mode=$command_request_session_mode
    tool_command=$command_request_command
    ;;
  *)
    resolved_session_mode=$session_mode
    ;;
esac

shared_tool_wrapper_bin_dir="@SHARED_TOOL_WRAPPER_BIN_DIR@"
if [ -n "$shared_tool_wrapper_bin_dir" ] && [ -d "$shared_tool_wrapper_bin_dir" ]; then
  export PATH="$shared_tool_wrapper_bin_dir:$PATH"
fi
if ! [ -r "$command_shell_init_file" ]; then
  command_shell_init_file=""
fi

if [ -r "$session_term_state_file" ]; then
  TERM=$(cat "$session_term_state_file")
  export TERM
fi
if [ -r "$session_columns_state_file" ]; then
  COLUMNS=$(cat "$session_columns_state_file")
  export COLUMNS
fi
if [ -r "$session_lines_state_file" ]; then
  LINES=$(cat "$session_lines_state_file")
  export LINES
fi
if [ -n "${COLUMNS:-}" ] && [ -n "${LINES:-}" ] && [ -e /dev/tty ] && command -v stty >/dev/null 2>&1; then
  stty rows "$LINES" cols "$COLUMNS" </dev/tty 2>/dev/null || true
fi

if [ ! -d "$target" ]; then
  target=@WORKSPACE_MOUNT@
fi

cd "$target"

show_session_banner=1
case "$resolved_session_mode" in
  command-attach-exec)
    show_session_banner=0
    ;;
esac

if [ "$show_session_banner" = "1" ]; then
  printf '\n\e[0m\e[1mWelcome to %s - %s\e[0m\n' "@BRANDING_NAME@" "@BRANDING_TAGLINE@"
  printf '[ vm: %s | mode: %s | workspace: %s ]\n' "@WORKLOAD_VM_NAME@" "$resolved_session_mode" "$target"
fi

case "$resolved_session_mode" in
  shell)
    @BASH@ -i || true
    exit 0
    ;;
  tool)
    if [ -n "$tool_command" ]; then
      exec env FIREBREAK_TOOL_COMMAND="$tool_command" @BASH@ -lc '
        command_shell_init_file="'"$command_shell_init_file"'"
        if [ -n "$command_shell_init_file" ]; then
          # shellcheck disable=SC1090
          . "$command_shell_init_file"
        fi
        eval "$FIREBREAK_TOOL_COMMAND"
        exec @BASH@ -i
      '
    fi
    exec @BASH@ -i
    ;;
  command-exec)
    if [ -n "$tool_command" ]; then
      exec @RUN_COMMAND_EXEC_SCRIPT@
    fi
    exec @BASH@ -i
    ;;
  command-attach-exec)
    mkdir -p @COMMAND_OUTPUT_MOUNT@
    printf '%s\n' "dev-console-start" > @COMMAND_OUTPUT_MOUNT@/attach_stage
    if [ -n "$tool_command" ]; then
      export guest_state_dir command_state_local command_state_shared
      export -f json_escape write_command_state
      exec env FIREBREAK_TOOL_COMMAND="$tool_command" FIREBREAK_COMMAND_REQUEST_ID="${FIREBREAK_COMMAND_REQUEST_ID:-}" @BASH@ "$attach_shell_flag" '
        status=0
        set +m
        stage_path=@COMMAND_OUTPUT_MOUNT@/attach_stage
        exit_code_path=@COMMAND_OUTPUT_MOUNT@/exit_code
        command_process_local="'"$command_process_local"'"
        command_process_shared="'"$command_process_shared"'"
        command_tty_local="'"$command_tty_local"'"
        command_tty_shared="'"$command_tty_shared"'"
        command_job_info_local="'"$command_job_info_local"'"
        command_signal_stream_shared="'"$command_signal_stream_shared"'"
        command_shell_init_file="'"$command_shell_init_file"'"
        command_process_monitor_pid=""
        command_signal_monitor_pid=""
        command_job_pid=""
        command_job_pgid=""
        command_tty_state=""
        command_signal_offset=0
        mkdir -p @COMMAND_OUTPUT_MOUNT@
        refresh_command_job_info() {
          command_job_pid=""
          command_job_pgid=""
          if [ -r "$command_job_info_local" ]; then
            # shellcheck disable=SC1090
            . "$command_job_info_local"
          fi
        }
        write_command_process_snapshot() {
          refresh_command_job_info
          child_pids=$(cat /proc/$$/task/$$/children 2>/dev/null || true)
          command_child_pids=""
          for tracked_pid in $child_pids; do
            if [ -n "$command_process_monitor_pid" ] && [ "$tracked_pid" = "$command_process_monitor_pid" ]; then
              continue
            fi
            command_child_pids="${command_child_pids}${command_child_pids:+ }$tracked_pid"
          done
          {
            printf "%s\n" "shell_pid=$$"
            printf "%s\n" "shell_tty=$(tty 2>/dev/null || true)"
            printf "%s\n" "command_job_pid=${command_job_pid:-}"
            printf "%s\n" "command_job_pgid=${command_job_pgid:-}"
            printf "%s\n" "term=${TERM:-}"
            printf "%s\n" "children=$child_pids"
            tracked_pids="$$"
            if [ -n "$child_pids" ]; then
              tracked_pids="$tracked_pids $child_pids"
            fi
            if [ -n "$command_job_pid" ]; then
              case " $tracked_pids " in
                *" $command_job_pid "*) ;;
                *) tracked_pids="$tracked_pids $command_job_pid" ;;
              esac
            fi
            if command -v ps >/dev/null 2>&1; then
              ps -o pid=,ppid=,pgid=,sess=,tpgid=,tty=,stat=,comm= -p $tracked_pids 2>/dev/null || true
            fi
            if [ -e /dev/tty ] && command -v stty >/dev/null 2>&1; then
              printf "%s\n" "stty=$(stty -a </dev/tty 2>/dev/null || true)"
            fi
            for tracked_pid in $tracked_pids; do
              if [ -r "/proc/$tracked_pid/cmdline" ]; then
                cmdline=$(tr "\0" " " </proc/$tracked_pid/cmdline 2>/dev/null || true)
                if [ -n "$cmdline" ]; then
                  printf "%s\n" "pid=$tracked_pid cmdline=$cmdline"
                fi
              fi
              if [ -r "/proc/$tracked_pid/wchan" ]; then
                wchan=$(cat /proc/$tracked_pid/wchan 2>/dev/null || true)
                if [ -n "$wchan" ]; then
                  printf "%s\n" "pid=$tracked_pid wchan=$wchan"
                fi
              fi
              for fd_num in 0 1 2; do
                if [ -e "/proc/$tracked_pid/fd/$fd_num" ]; then
                  fd_target=$(readlink /proc/$tracked_pid/fd/$fd_num 2>/dev/null || true)
                  if [ -n "$fd_target" ]; then
                    printf "%s\n" "pid=$tracked_pid fd$fd_num=$fd_target"
                  fi
                fi
              done
            done
          } >"$command_process_local"
          if [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
            cp "$command_process_local" "$command_process_shared"
          fi
          {
            printf "%s\n" "shell_pid=$$"
            printf "%s\n" "shell_tty=$(tty 2>/dev/null || true)"
            printf "%s\n" "monitor_pid=${command_process_monitor_pid:-}"
            printf "%s\n" "command_job_pid=${command_job_pid:-}"
            printf "%s\n" "command_job_pgid=${command_job_pgid:-}"
            printf "%s\n" "command_children=${command_child_pids:-}"
            if command -v ps >/dev/null 2>&1; then
              tty_tracked_pids="$$"
              if [ -n "$command_process_monitor_pid" ]; then
                tty_tracked_pids="$tty_tracked_pids $command_process_monitor_pid"
              fi
              if [ -n "$command_child_pids" ]; then
                tty_tracked_pids="$tty_tracked_pids $command_child_pids"
              fi
              ps -o pid=,ppid=,pgid=,sess=,tpgid=,tty=,stat=,comm= -p $tty_tracked_pids 2>/dev/null || true
            fi
            if [ -e /dev/tty ] && command -v stty >/dev/null 2>&1; then
              printf "%s\n" "stty=$(stty -a </dev/tty 2>/dev/null || true)"
            fi
          } >"$command_tty_local"
          if [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
            cp "$command_tty_local" "$command_tty_shared"
          fi
        }
        start_command_process_monitor() {
          exec 9>&2
          exec 2>/dev/null
          (
            while true; do
              write_command_process_snapshot
              if [ -f "$exit_code_path" ]; then
                exit 0
              fi
              sleep 1
            done
          ) </dev/null >/dev/null 2>&1 &
          command_process_monitor_pid=$!
          exec 2>&9
          exec 9>&-
        }
        stop_command_process_monitor() {
          if [ -n "$command_process_monitor_pid" ]; then
            kill "$command_process_monitor_pid" 2>/dev/null || true
            wait "$command_process_monitor_pid" 2>/dev/null || true
            command_process_monitor_pid=""
          fi
        }
        handle_command_signal_requests() {
          refresh_command_job_info
          [ -r "$command_signal_stream_shared" ] || return 0
          snapshot_size=$(wc -c <"$command_signal_stream_shared" 2>/dev/null || echo "$command_signal_offset")
          if [ "$snapshot_size" -le "$command_signal_offset" ]; then
            return 0
          fi
          signal_count=$((snapshot_size - command_signal_offset))
          while IFS= read -r signal_name; do
            case "$signal_name" in
              INT)
                if [ -n "$command_job_pgid" ]; then
                  kill -INT -- "-$command_job_pgid" 2>/dev/null || true
                fi
                ;;
              TERM)
                if [ -n "$command_job_pgid" ]; then
                  kill -TERM -- "-$command_job_pgid" 2>/dev/null || true
                fi
                ;;
              KILL)
                if [ -n "$command_job_pgid" ]; then
                  kill -KILL -- "-$command_job_pgid" 2>/dev/null || true
                fi
                ;;
            esac
          done <<EOF
$(dd if="$command_signal_stream_shared" bs=1 skip="$command_signal_offset" count="$signal_count" status=none 2>/dev/null || true)
EOF
          command_signal_offset=$snapshot_size
        }
        start_command_signal_monitor() {
          : >"$command_signal_stream_shared"
          command_signal_offset=0
          (
            while true; do
              handle_command_signal_requests
              if [ -f "$exit_code_path" ]; then
                exit 0
              fi
              sleep 0.1
            done
          ) </dev/null >/dev/null 2>&1 &
          command_signal_monitor_pid=$!
        }
        stop_command_signal_monitor() {
          if [ -n "$command_signal_monitor_pid" ]; then
            kill "$command_signal_monitor_pid" 2>/dev/null || true
            wait "$command_signal_monitor_pid" 2>/dev/null || true
            command_signal_monitor_pid=""
          fi
        }
        rebind_command_stdio() {
          if [ -e /dev/tty ]; then
            exec </dev/tty >/dev/tty 2>/dev/tty
          fi
        }
        run_command_in_foreground_job() {
          command_status=0
          command_job_pid=""
          command_job_pgid=""
          command_foreground_helper="'"$command_foreground_helper_local"'"
          rm -f "$command_job_info_local"
          shell_pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -cd "0-9" || true)
          if [ -z "$shell_pgid" ]; then
            shell_pgid=$$
          fi
          if [ -x @PYTHON3@ ] && [ -e /dev/tty ]; then
            cat >"$command_foreground_helper" <<'"'"'PY'"'"'
import os
import signal
import subprocess
import sys

command = os.environ["FIREBREAK_TOOL_COMMAND"]
job_info_path = os.environ["FIREBREAK_COMMAND_JOB_INFO"]
shell_pgid = int(os.environ["FIREBREAK_SHELL_PGID"])
tty_fd = os.open("/dev/tty", os.O_RDWR)
for sig in (signal.SIGTTOU, signal.SIGTTIN, signal.SIGTSTP):
    signal.signal(sig, signal.SIG_IGN)
proc = None
status = 1
try:
    proc = subprocess.Popen(
        command,
        shell=True,
        stdin=tty_fd,
        stdout=tty_fd,
        stderr=tty_fd,
        process_group=0,
        close_fds=True,
    )
    with open(job_info_path, "w", encoding="utf-8") as handle:
        handle.write(f"command_job_pid={proc.pid}\n")
        handle.write(f"command_job_pgid={proc.pid}\n")
    os.tcsetpgrp(tty_fd, proc.pid)
    status = proc.wait()
finally:
    try:
        os.tcsetpgrp(tty_fd, shell_pgid)
    except OSError:
        pass
    os.close(tty_fd)
if status < 0:
    sys.exit(128 + (-status))
sys.exit(status)
PY
            if FIREBREAK_COMMAND_JOB_INFO="$command_job_info_local" \
               FIREBREAK_SHELL_PGID="$shell_pgid" \
               @PYTHON3@ "$command_foreground_helper"
            then
              command_status=0
            else
              command_status=$?
            fi
          else
            if eval "$FIREBREAK_TOOL_COMMAND"; then
              command_status=0
            else
              command_status=$?
            fi
          fi
          refresh_command_job_info
          rm -f "$command_job_info_local"
          command_job_pid=""
          command_job_pgid=""
          return "$command_status"
        }
        configure_command_tty() {
          if [ -e /dev/tty ] && command -v stty >/dev/null 2>&1; then
            command_tty_state=$(stty -g </dev/tty 2>/dev/null || true)
            stty sane </dev/tty 2>/dev/null || true
          fi
        }
        emit_command_stream_marker() {
          marker_name=$1
          marker_value=${2-}
          if [ ! -e /dev/tty ]; then
            return 0
          fi
          if [ -n "$marker_value" ]; then
            printf "\033]9001;firebreak;%s:%s\007" "$marker_name" "$marker_value" >/dev/tty 2>/dev/null || true
          else
            printf "\033]9001;firebreak;%s\007" "$marker_name" >/dev/tty 2>/dev/null || true
          fi
        }
        restore_command_tty() {
          if [ -n "$command_tty_state" ] && [ -e /dev/tty ]; then
            stty "$command_tty_state" </dev/tty 2>/dev/null || true
            command_tty_state=""
          fi
        }
        trap restore_command_tty EXIT INT TERM
        if [ -n "$command_shell_init_file" ]; then
          # shellcheck disable=SC1090
          . "$command_shell_init_file"
        fi
        if command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
          write_command_state bootstrap-wait running command-attach-exec 0
          if firebreak-bootstrap-wait; then
            :
          else
            status=$?
            write_command_state bootstrap-wait error command-attach-exec "$status"
            printf "%s\n" "$status" >"$exit_code_path"
            printf "%s\n" "bootstrap-wait-error:$status" >"$stage_path"
            exit "$status"
          fi
        fi
        write_command_state command-start running command-attach-exec 0
        printf "%s\n" "command-start" >"$stage_path"
        rebind_command_stdio
        configure_command_tty
        emit_command_stream_marker command-start
        write_command_process_snapshot
        start_command_process_monitor
        start_command_signal_monitor
        run_command_in_foreground_job || status=$?
        stop_command_signal_monitor
        stop_command_process_monitor
        write_command_process_snapshot
        restore_command_tty
        printf "%s\n" "$status" >"$exit_code_path"
        write_command_state command-exit completed command-attach-exec "$status"
        printf "%s\n" "command-exit:$status" >"$stage_path"
        emit_command_stream_marker command-exit "$status"
        exit "$status"
      '
    fi
    write_command_state interactive-shell-fallback fallback command-attach-exec 0
    printf '%s\n' "interactive-shell-fallback" > @COMMAND_OUTPUT_MOUNT@/attach_stage
    exec @BASH@ -i
    ;;
  *)
    printf 'unknown tool session mode: %s\n' "$session_mode" >&2
    exec @BASH@ -i
    ;;
esac
