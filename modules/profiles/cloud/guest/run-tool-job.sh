set -eu

prompt_file=@TOOL_PROMPT_FILE@
stdout_path=@COMMAND_OUTPUT_MOUNT@/stdout
stderr_path=@COMMAND_OUTPUT_MOUNT@/stderr
exit_code_path=@COMMAND_OUTPUT_MOUNT@/exit_code
command_file=$(mktemp)
trap 'rm -f "$command_file"' EXIT INT TERM

cat >"$command_file" <<'EOF'
@TOOL_PROMPT_COMMAND@
EOF

if ! [ -s "$command_file" ]; then
  echo "tool prompt execution is not configured for this VM" >&2
  exit 1
fi

if ! [ -r "$prompt_file" ]; then
  echo "tool prompt file is missing: $prompt_file" >&2
  exit 1
fi

FIREBREAK_TOOL_PROMPT=$(@CAT@ "$prompt_file")
if [ -z "$FIREBREAK_TOOL_PROMPT" ]; then
  echo "tool prompt is empty" >&2
  exit 1
fi
export FIREBREAK_TOOL_PROMPT

rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

status=0
@RUNUSER@ -u @DEV_USER@ -- @BASH@ -ic "$(@CAT@ "$command_file")" >"$stdout_path" 2>"$stderr_path" || status=$?
printf '%s\n' "$status" >"$exit_code_path"

@SYSTEMCTL@ poweroff --no-block >/dev/null 2>&1 || true
exit "$status"
