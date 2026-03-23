set -eu

require_pattern() {
  output=$1
  pattern=$2
  description=$3

  if ! printf '%s\n' "$output" | grep -F -q -- "$pattern"; then
    printf '%s\n' "$output" >&2
    echo "missing $description" >&2
    exit 1
  fi
}

vms_output=$(@FIREBREAK_CLI_BIN@ vms)
require_pattern "$vms_output" "codex" "codex VM listing"
require_pattern "$vms_output" "claude-code" "claude-code VM listing"

vms_json=$(@FIREBREAK_CLI_BIN@ vms --json)
require_pattern "$vms_json" '"name": "codex"' "codex VM JSON listing"
require_pattern "$vms_json" '"name": "claude-code"' "claude-code VM JSON listing"

run_codex_output=$(@FIREBREAK_CLI_BIN@ run codex -- --version)
require_pattern "$run_codex_output" '__VM__codex' "codex run delegation"
require_pattern "$run_codex_output" '__MODE__unset' "default run mode passthrough"
require_pattern "$run_codex_output" '__ARG__--version' "codex forwarded argument"

run_claude_shell_output=$(@FIREBREAK_CLI_BIN@ run claude-code --shell -- prompt.txt)
require_pattern "$run_claude_shell_output" '__VM__claude-code' "claude-code run delegation"
require_pattern "$run_claude_shell_output" '__MODE__shell' "shell mode override"
require_pattern "$run_claude_shell_output" '__ARG__prompt.txt' "claude-code forwarded argument"

set +e
unknown_vm_output=$(@FIREBREAK_CLI_BIN@ run unknown 2>&1)
unknown_vm_status=$?
set -e

if [ "$unknown_vm_status" -eq 0 ] || ! printf '%s\n' "$unknown_vm_output" | grep -F -q "run 'firebreak vms'"; then
  printf '%s\n' "$unknown_vm_output" >&2
  echo "CLI surface smoke did not reject an unknown VM cleanly" >&2
  exit 1
fi

printf '%s\n' "Firebreak CLI surface smoke test passed"
