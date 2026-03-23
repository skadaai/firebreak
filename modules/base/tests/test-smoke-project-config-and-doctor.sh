set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this project-config smoke test from inside the Firebreak repository" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-/cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-project-config.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

project_dir=$smoke_tmp_dir/project
mkdir -p "$project_dir"

unset AGENT_CONFIG
unset AGENT_CONFIG_HOST_PATH
unset FIREBREAK_VM_MODE
unset CODEX_CONFIG
unset CODEX_CONFIG_HOST_PATH
unset CLAUDE_CONFIG
unset CLAUDE_CONFIG_HOST_PATH

firebreak_cmd() {
  (
    cd "$project_dir"
    nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- "$@"
  )
}

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

init_stdout=$(firebreak_cmd init --stdout)
require_pattern "$init_stdout" "AGENT_CONFIG=workspace" "default AGENT_CONFIG template entry"
require_pattern "$init_stdout" "# FIREBREAK_VM_MODE=run" "default FIREBREAK_VM_MODE template entry"

firebreak_cmd init >/dev/null
if ! [ -f "$project_dir/.firebreak.env" ]; then
  echo "project-config smoke did not write .firebreak.env" >&2
  exit 1
fi

cat >"$project_dir/.firebreak.env" <<EOF
AGENT_CONFIG=host
AGENT_CONFIG_HOST_PATH=~/shared-agent-config
CODEX_CONFIG=workspace
FIREBREAK_TASK_STATE_DIR=/tmp/internal-only
EOF

doctor_output=$(AGENT_CONFIG=vm firebreak_cmd doctor)
require_pattern "$doctor_output" "codex_config" "doctor codex summary"
require_pattern "$doctor_output" "workspace ($project_dir/.codex)" "Codex-specific config precedence"
require_pattern "$doctor_output" "claude_config" "doctor claude summary"
require_pattern "$doctor_output" "vm (/var/lib/dev/.claude)" "environment overrides project file for generic agent mode"
require_pattern "$doctor_output" "Remove unsupported keys from .firebreak.env" "doctor unsupported-key guidance"

doctor_json=$(AGENT_CONFIG=vm firebreak_cmd doctor --json)
require_pattern "$doctor_json" '"project_config_source": "project-default"' "doctor json project config source"
require_pattern "$doctor_json" '"ignored_config_keys": ["FIREBREAK_TASK_STATE_DIR"]' "doctor json ignored key list"
require_pattern "$doctor_json" '"codex": {' "doctor json codex section"
require_pattern "$doctor_json" '"mode": "workspace"' "doctor json Codex mode"
require_pattern "$doctor_json" "\"path\": \"$project_dir/.codex\"" "doctor json Codex path"
require_pattern "$doctor_json" '"claude-code": {' "doctor json Claude section"
require_pattern "$doctor_json" '"mode": "vm"' "doctor json Claude mode"
require_pattern "$doctor_json" '"vm_mode": "run"' "doctor json default public VM mode"

printf '%s\n' "Firebreak project-config and doctor smoke test passed"
