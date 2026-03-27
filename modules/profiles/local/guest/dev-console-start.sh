set -eu

target=@WORKSPACE_MOUNT@
session_mode=shell
agent_command=@AGENT_COMMAND@
guest_state_dir=/run/firebreak-agent
command_state_local=$guest_state_dir/command-state.json
command_state_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-state.json

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
          if ! firebreak-bootstrap-wait; then
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
      exec env FIREBREAK_AGENT_COMMAND="$agent_command" @BASH@ -ic '
        status=0
        stage_path=@AGENT_EXEC_OUTPUT_MOUNT@/attach_stage
        exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code
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
        if command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
          write_command_state bootstrap-wait running agent-attach-exec 0
          if ! firebreak-bootstrap-wait; then
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
        eval "$FIREBREAK_AGENT_COMMAND" || status=$?
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
