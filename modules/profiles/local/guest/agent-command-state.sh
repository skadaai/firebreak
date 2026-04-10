guest_state_dir=/run/firebreak-worker
command_state_local=$guest_state_dir/command-state.json
command_state_shared=@AGENT_EXEC_OUTPUT_MOUNT@/command-state.json

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
  "request_id": "$(json_escape "${FIREBREAK_AGENT_REQUEST_ID:-}")",
  "phase": "$(json_escape "$command_phase")",
  "status": "$(json_escape "$command_status")",
  "detail": "$(json_escape "$command_detail")",
  "command": "$(json_escape "${FIREBREAK_AGENT_COMMAND:-}")",
  "exit_code": $command_exit_code,
  "updated_at": "$updated_at"
}
EOF
  if [ -d @AGENT_EXEC_OUTPUT_MOUNT@ ]; then
    if ! cp "$command_state_local" "$command_state_shared"; then
      echo "failed to sync command state from $command_state_local to $command_state_shared" >&2
      exit 1
    fi
    chmod 0666 "$command_state_shared" 2>/dev/null || true
  fi
}
