set -eu

target=@WORKSPACE_MOUNT@
session_mode=shell
agent_command=@AGENT_COMMAND@
guest_state_dir=/run/firebreak-agent
command_state_local=$guest_state_dir/command-state.json
command_state_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-state.json
command_process_local=$guest_state_dir/command-processes.txt
command_process_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-processes.txt
session_term_state_file=$guest_state_dir/session-term
session_columns_state_file=$guest_state_dir/session-columns
session_lines_state_file=$guest_state_dir/session-lines
attach_shell_flag=-ic

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
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
    cp "$command_state_local" "$command_state_shared"
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

case "$session_mode:$agent_command" in
  agent-attach-exec:codex|agent:codex)
    if [ -x /run/agent-tools-host/.bun/bin/codex ]; then
      agent_command="/run/agent-tools-host/.bun/bin/codex"
    fi
    attach_shell_flag=-lc
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
  "phase": "$(printf "%s" "$command_phase" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "status": "$(printf "%s" "$command_status" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "detail": "$(printf "%s" "$command_detail" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "command": "$(printf "%s" "$FIREBREAK_AGENT_COMMAND" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "exit_code": $command_exit_code,
  "updated_at": "$updated_at"
}
EOF
          if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
            cp "'"$command_state_local"'" "'"$command_state_shared"'"
          fi
        }
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
      '
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
        command_process_monitor_pid=""
        command_tty_state=""
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
  "phase": "$(printf "%s" "$command_phase" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "status": "$(printf "%s" "$command_status" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "detail": "$(printf "%s" "$command_detail" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "command": "$(printf "%s" "$FIREBREAK_AGENT_COMMAND" | sed '"'"'s/\\/\\\\/g; s/"/\\"/g'"'"')",
  "exit_code": $command_exit_code,
  "updated_at": "$updated_at"
}
EOF
          if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
            cp "'"$command_state_local"'" "'"$command_state_shared"'"
          fi
        }
        write_command_process_snapshot() {
          child_pids=$(cat /proc/$$/task/$$/children 2>/dev/null || true)
          {
            printf "%s\n" "shell_pid=$$"
            printf "%s\n" "shell_tty=$(tty 2>/dev/null || true)"
            printf "%s\n" "term=${TERM:-}"
            printf "%s\n" "children=$child_pids"
            tracked_pids="$$"
            if [ -n "$child_pids" ]; then
              tracked_pids="$tracked_pids $child_pids"
            fi
            if command -v ps >/dev/null 2>&1; then
              ps -o pid=,ppid=,pgid=,sess=,tpgid=,tty=,stat=,comm= -p $tracked_pids 2>/dev/null || true
            fi
            if tty >/dev/null 2>&1 && command -v stty >/dev/null 2>&1; then
              printf "%s\n" "stty=$(stty -a 2>/dev/null || true)"
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
        configure_command_tty() {
          if tty >/dev/null 2>&1 && command -v stty >/dev/null 2>&1; then
            command_tty_state=$(stty -g 2>/dev/null || true)
            stty raw -echo min 1 time 0 2>/dev/null || true
          fi
        }
        restore_command_tty() {
          if [ -n "$command_tty_state" ]; then
            stty "$command_tty_state" 2>/dev/null || true
            command_tty_state=""
          fi
        }
        trap restore_command_tty EXIT INT TERM
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
        configure_command_tty
        write_command_process_snapshot
        start_command_process_monitor
        eval "$FIREBREAK_AGENT_COMMAND" || status=$?
        stop_command_process_monitor
        write_command_process_snapshot
        restore_command_tty
        printf "%s\n" "$status" >"$exit_code_path"
        write_command_state command-exit completed agent-attach-exec "$status"
        printf "%s\n" "command-exit:$status" >"$stage_path"
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
