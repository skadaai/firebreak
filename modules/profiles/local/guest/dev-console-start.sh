#!/usr/bin/env bash
set -eu

if [ -n "${PATH:-}" ]; then
  export PATH="/run/current-system/sw/bin:$PATH"
else
  export PATH="/run/current-system/sw/bin"
fi

target=@WORKSPACE_MOUNT@
session_mode=shell
agent_command=@AGENT_COMMAND@
agent_tools_mount=@AGENT_TOOLS_MOUNT@
guest_state_dir=/run/firebreak-worker
command_state_local=$guest_state_dir/command-state.json
command_state_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
command_process_local=$guest_state_dir/command-processes.txt
command_process_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-processes.txt
command_tty_local=$guest_state_dir/command-tty.txt
command_tty_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-tty.txt
command_job_info_local=$guest_state_dir/command-job.env
command_foreground_helper_local=$guest_state_dir/command-foreground.py
command_signal_stream_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-signals.stream
session_term_state_file=$guest_state_dir/session-term
session_columns_state_file=$guest_state_dir/session-columns
session_lines_state_file=$guest_state_dir/session-lines
command_shell_init_file=@COMMAND_SHELL_INIT_FILE@
attach_shell_flag=-ic
attach_shell_flag=-lc

json_escape() {
  printf '%s' "$1" | @PYTHON3@ -c 'import json, sys; print(json.dumps(sys.stdin.read())[1:-1], end="")'
}

write_command_state() {
  command_phase=$1
  command_status=$2
  command_detail=$3
  command_exit_code=$4
  updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$guest_state_dir"
  cat >"$command_state_local" <<EOF
{
  "source": "guest-command",
  "phase": "$(json_escape "$command_phase")",
  "status": "$(json_escape "$command_status")",
  "detail": "$(json_escape "$command_detail")",
  "command": "$(json_escape "$agent_command")",
  "exit_code": $command_exit_code,
  "updated_at": "$updated_at"
}
EOF
  if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
    cp "$command_state_local" "$command_state_shared" 2>/dev/null || true
  fi
}

if [ -r @START_DIR_FILE@ ]; then
  target=$(cat @START_DIR_FILE@)
fi

if [ -r @AGENT_SESSION_MODE_FILE@ ]; then
  session_mode=$(cat @AGENT_SESSION_MODE_FILE@)
fi

if [ -r @AGENT_COMMAND_FILE@ ]; then
  agent_command=$(cat @AGENT_COMMAND_FILE@)
fi

shared_tool_wrapper_bin_dir="@SHARED_AGENT_WRAPPER_BIN_DIR@"
if [ -n "$shared_tool_wrapper_bin_dir" ] && [ -d "$shared_tool_wrapper_bin_dir" ]; then
  export PATH="$shared_tool_wrapper_bin_dir:$PATH"
fi
if ! [ -r "$command_shell_init_file" ]; then
  command_shell_init_file=""
fi

case "$session_mode:$agent_command" in
  agent-attach-exec:codex|agent:codex)
    if [ -x "$agent_tools_mount/.bun/bin/codex" ]; then
      agent_command="$agent_tools_mount/.bun/bin/codex"
    fi
    ;;
esac

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

prepare_codex_command_wrapper() {
  codex_runtime_dir=$guest_state_dir/codex
  codex_home_dir=$codex_runtime_dir/home
  codex_sqlite_dir=$codex_runtime_dir/sqlite
  codex_config_dir=$codex_home_dir/.codex
  codex_wrapper_path=$codex_runtime_dir/command.sh
  mkdir -p "$codex_config_dir" "$codex_sqlite_dir"
  cat >"$codex_config_dir/config.toml" <<EOF
check_for_update_on_startup = false
cli_auth_credentials_store = "ephemeral"

[tui]
alternate_screen = "never"
EOF
  cat >"$codex_wrapper_path" <<EOF
#!/usr/bin/env bash
set -eu
export HOME='$(printf '%s' "$codex_home_dir" | sed "s/'/'\\\\''/g")'
export CODEX_HOME='$(printf '%s' "$codex_config_dir" | sed "s/'/'\\\\''/g")'
export CODEX_CONFIG_DIR='$(printf '%s' "$codex_config_dir" | sed "s/'/'\\\\''/g")'
export CODEX_SQLITE_HOME='$(printf '%s' "$codex_sqlite_dir" | sed "s/'/'\\\\''/g")'
mkdir -p "\$CODEX_HOME" "\$CODEX_SQLITE_HOME"
cd '$(printf '%s' "$target" | sed "s/'/'\\\\''/g")'
exec '$(printf '%s' "$agent_tools_mount/.bun/bin/codex" | sed "s/'/'\\\\''/g")' --no-alt-screen
EOF
  chmod 0444 "$codex_wrapper_path"
  agent_command="@BASH@ $(printf '%s' "$codex_wrapper_path" | sed "s/'/'\\\\''/g")"
}

case "$session_mode:$agent_command" in
  agent-attach-exec:"$agent_tools_mount"/.bun/bin/codex|agent:"$agent_tools_mount"/.bun/bin/codex)
    prepare_codex_command_wrapper
    ;;
esac

show_session_banner=1
case "$session_mode" in
  agent-attach-exec)
    show_session_banner=0
    ;;
esac

if [ "$show_session_banner" = "1" ]; then
  printf '\n\e[0m\e[1mWelcome to %s - %s\e[0m\n' "@BRANDING_NAME@" "@BRANDING_TAGLINE@"
  printf '[ vm: %s | mode: %s | workspace: %s ]\n' "@AGENT_VM_NAME@" "$session_mode" "$target"
fi

case "$session_mode" in
  shell)
    @BASH@ -i || true
    exit 0
    ;;
  agent)
    if [ -n "$agent_command" ]; then
      exec env FIREBREAK_AGENT_COMMAND="$agent_command" @BASH@ -lc '
        command_shell_init_file="'"$command_shell_init_file"'"
        if [ -n "$command_shell_init_file" ]; then
          # shellcheck disable=SC1090
          . "$command_shell_init_file"
        fi
        eval "$FIREBREAK_AGENT_COMMAND"
        exec @BASH@ -i
      '
    fi
    exec @BASH@ -i
    ;;
  agent-exec)
    if [ -n "$agent_command" ]; then
      if [ -n "$command_shell_init_file" ]; then
        # shellcheck disable=SC1090
        . "$command_shell_init_file"
      fi
      export FIREBREAK_AGENT_COMMAND="$agent_command"
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
      write_command_state command-start running agent-exec 0
      eval "$FIREBREAK_AGENT_COMMAND" >"$stdout_path" 2>"$stderr_path" || status=$?
      write_command_state command-exit completed agent-exec "$status"
      printf "%s\n" "$status" >"$exit_code_path"
      sudo poweroff >/dev/null 2>&1 || true
      exit "$status"
    fi
    exec @BASH@ -i
    ;;
  agent-attach-exec)
    mkdir -p @AGENT_EXEC_OUTPUT_MOUNT@
    printf '%s\n' "dev-console-start" > @AGENT_EXEC_OUTPUT_MOUNT@/attach_stage
    if [ -n "$agent_command" ]; then
      exec env FIREBREAK_AGENT_COMMAND="$agent_command" @BASH@ "$attach_shell_flag" '
        status=0
        set +m
        stage_path=@AGENT_EXEC_OUTPUT_MOUNT@/attach_stage
        exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code
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
        mkdir -p @AGENT_EXEC_OUTPUT_MOUNT@
        write_command_state() {
          command_phase=$1
          command_status=$2
          command_detail=$3
          command_exit_code=$4
          updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          mkdir -p "'"$guest_state_dir"'"
          cat >"'"$command_state_local"'" <<EOF
{
  "source": "guest-command",
  "phase": "$(printf "%s" "$command_phase" | @PYTHON3@ -c '"'"'import json, sys; print(json.dumps(sys.stdin.read())[1:-1], end="")'"'"')",
  "status": "$(printf "%s" "$command_status" | @PYTHON3@ -c '"'"'import json, sys; print(json.dumps(sys.stdin.read())[1:-1], end="")'"'"')",
  "detail": "$(printf "%s" "$command_detail" | @PYTHON3@ -c '"'"'import json, sys; print(json.dumps(sys.stdin.read())[1:-1], end="")'"'"')",
  "command": "$(printf "%s" "$FIREBREAK_AGENT_COMMAND" | @PYTHON3@ -c '"'"'import json, sys; print(json.dumps(sys.stdin.read())[1:-1], end="")'"'"')",
  "exit_code": $command_exit_code,
  "updated_at": "$updated_at"
}
EOF
          if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
            cp "'"$command_state_local"'" "'"$command_state_shared"'" 2>/dev/null || true
          fi
        }
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
          if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
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
          if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
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

command = os.environ["FIREBREAK_AGENT_COMMAND"]
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
            if eval "$FIREBREAK_AGENT_COMMAND"; then
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
          write_command_state bootstrap-wait running agent-attach-exec 0
          if firebreak-bootstrap-wait; then
            :
          else
            status=$?
            write_command_state bootstrap-wait error agent-attach-exec "$status"
            printf "%s\n" "$status" >"$exit_code_path"
            printf "%s\n" "bootstrap-wait-error:$status" >"$stage_path"
            sudo poweroff >/dev/null 2>&1 || true
            exit "$status"
          fi
        fi
        write_command_state command-start running agent-attach-exec 0
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
        write_command_state command-exit completed agent-attach-exec "$status"
        printf "%s\n" "command-exit:$status" >"$stage_path"
        emit_command_stream_marker command-exit "$status"
        sudo poweroff >/dev/null 2>&1 || true
        exit "$status"
      '
    fi
    write_command_state interactive-shell-fallback fallback agent-attach-exec 0
    printf '%s\n' "interactive-shell-fallback" > @AGENT_EXEC_OUTPUT_MOUNT@/attach_stage
    exec @BASH@ -i
    ;;
  *)
    printf 'unknown agent session mode: %s\n' "$session_mode" >&2
    exec @BASH@ -i
    ;;
esac
