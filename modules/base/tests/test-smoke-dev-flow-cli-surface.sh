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

top_level_help_output=$(@DEV_FLOW_CLI_BIN@ --help 2>&1)
require_pattern "$top_level_help_output" "usage:" "top-level help usage text"

validate_output=$(@DEV_FLOW_CLI_BIN@ validate run test-smoke-codex)
require_pattern "$validate_output" "__DEV_FLOW__validate" "validate delegation"
require_pattern "$validate_output" "__ARG__run" "validate run subcommand passthrough"
require_pattern "$validate_output" "__ARG__test-smoke-codex" "validate suite passthrough"

workspace_output=$(@DEV_FLOW_CLI_BIN@ workspace create --workspace-id spec-010 --branch dev-flow/spec-010)
require_pattern "$workspace_output" "__DEV_FLOW__workspace" "workspace delegation"
require_pattern "$workspace_output" "__ARG__create" "workspace create subcommand passthrough"
require_pattern "$workspace_output" "__ARG__--workspace-id" "workspace id flag passthrough"
require_pattern "$workspace_output" "__ARG__spec-010" "workspace id value passthrough"

loop_output=$(@DEV_FLOW_CLI_BIN@ loop run --workspace-id spec-010 --spec specs/010/SPEC.md --plan "plan" --validation-suite test-smoke-codex)
require_pattern "$loop_output" "__DEV_FLOW__loop" "loop delegation"
require_pattern "$loop_output" "__ARG__run" "loop run subcommand passthrough"
require_pattern "$loop_output" "__ARG__--workspace-id" "loop workspace flag passthrough"
require_pattern "$loop_output" "__ARG__spec-010" "loop workspace value passthrough"

printf '%s\n' "dev-flow CLI surface smoke test passed"
