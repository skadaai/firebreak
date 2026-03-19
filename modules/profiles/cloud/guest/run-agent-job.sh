set -eu

prompt_file=@AGENT_PROMPT_FILE@
agent_prompt_command=@AGENT_PROMPT_COMMAND@
stdout_path=@AGENT_EXEC_OUTPUT_MOUNT@/stdout
stderr_path=@AGENT_EXEC_OUTPUT_MOUNT@/stderr
exit_code_path=@AGENT_EXEC_OUTPUT_MOUNT@/exit_code

if [ -z "$agent_prompt_command" ]; then
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

rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

status=0
@BASH@ -ic "$agent_prompt_command" >"$stdout_path" 2>"$stderr_path" || status=$?
printf '%s\n' "$status" >"$exit_code_path"

sudo poweroff >/dev/null 2>&1 || true
exit "$status"
