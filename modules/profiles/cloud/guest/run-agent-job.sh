set -eu

prompt_file=@AGENT_PROMPT_FILE@
stdout_path=@AGENT_EXEC_OUTPUT_MOUNT@/stdout
stderr_path=@AGENT_EXEC_OUTPUT_MOUNT@/stderr
exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code
command_file=$(mktemp)
trap 'rm -f "$command_file"' EXIT INT TERM

cat >"$command_file" <<'EOF'
@AGENT_PROMPT_COMMAND@
EOF

if ! [ -s "$command_file" ]; then
  echo "agent prompt execution is not configured for this VM" >&2
  exit 1
fi

if ! [ -r "$prompt_file" ]; then
  echo "agent prompt file is missing: $prompt_file" >&2
  exit 1
fi

FIREBREAK_AGENT_PROMPT=$(@CAT@ "$prompt_file")
if [ -z "$FIREBREAK_AGENT_PROMPT" ]; then
  echo "agent prompt is empty" >&2
  exit 1
fi
export FIREBREAK_AGENT_PROMPT

rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

status=0
@RUNUSER@ -u @DEV_USER@ -- @BASH@ -ic "$(@CAT@ "$command_file")" >"$stdout_path" 2>"$stderr_path" || status=$?
printf '%s\n' "$status" >"$exit_code_path"

@SYSTEMCTL@ poweroff --no-block >/dev/null 2>&1 || true
exit "$status"
