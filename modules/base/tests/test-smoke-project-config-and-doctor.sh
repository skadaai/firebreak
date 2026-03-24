set -eu

repo_root=@REPO_ROOT@
if ! [ -f "$repo_root/flake.nix" ]; then
  echo "project-config smoke could not resolve the Firebreak source root" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-project-config.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

project_dir=$smoke_tmp_dir/project
mkdir -p "$project_dir"

unset AGENT_CONFIG
unset AGENT_CONFIG_HOST_PATH
unset FIREBREAK_PROJECT_CONFIG_FILE
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

init_template_stdout=$(firebreak_cmd init --non-interactive --stdout)
require_pattern "$init_template_stdout" "AGENT_CONFIG=workspace" "default AGENT_CONFIG template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_VM_MODE=run" "default FIREBREAK_VM_MODE template entry"

set +e
interactive_init_output=$(
  printf '1\n1\nn\nn\ny\n' | firebreak_cmd init 2>&1
)
interactive_init_status=$?
set -e

if [ "$interactive_init_status" -ne 0 ]; then
  printf '%s\n' "$interactive_init_output" >&2
  echo "interactive firebreak init did not complete successfully" >&2
  exit 1
fi

if ! [ -f "$project_dir/.firebreak.env" ]; then
  echo "project-config smoke did not write .firebreak.env" >&2
  exit 1
fi

interactive_init_file=$(cat "$project_dir/.firebreak.env")
require_pattern "$interactive_init_file" "AGENT_CONFIG=workspace" "interactive init AGENT_CONFIG entry"
require_pattern "$interactive_init_file" "FIREBREAK_VM_MODE=run" "interactive init FIREBREAK_VM_MODE entry"

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
require_pattern "$doctor_output" "cwd_whitespace" "doctor cwd compatibility reporting"

doctor_verbose_output=$(AGENT_CONFIG=vm firebreak_cmd doctor --verbose)
require_pattern "$doctor_verbose_output" "Details" "doctor verbose details header"
require_pattern "$doctor_verbose_output" "project_root_source" "doctor verbose project root source"
require_pattern "$doctor_verbose_output" "git_common_dir" "doctor verbose git common dir"

doctor_json=$(AGENT_CONFIG=vm firebreak_cmd doctor --json)
DOCTOR_JSON=$doctor_json PROJECT_DIR=$project_dir python3 - <<'PY'
import json
import os
import sys

obj = json.loads(os.environ["DOCTOR_JSON"])
project_dir = os.environ["PROJECT_DIR"]

assert obj["project_config_source"] == "project-default"
assert "FIREBREAK_TASK_STATE_DIR" in obj["ignored_config_keys"]
assert obj["agents"]["codex"]["mode"] == "workspace"
assert obj["agents"]["codex"]["path"] == f"{project_dir}/.codex"
assert obj["agents"]["claude-code"]["mode"] == "vm"
assert obj["vm_mode"] == "run"
PY

doctor_verbose_json=$(AGENT_CONFIG=vm firebreak_cmd doctor --verbose --json)
DOCTOR_VERBOSE_JSON=$doctor_verbose_json PROJECT_DIR=$project_dir python3 - <<'PY'
import json
import os
import sys

obj = json.loads(os.environ["DOCTOR_VERBOSE_JSON"])
details = obj["details"]
project_dir = os.environ["PROJECT_DIR"]

assert obj["project_root_source"] == "cwd"
assert obj["git_common_dir"] == "unknown"
assert obj["cwd_whitespace"] is False
assert details["cwd"] == project_dir
assert details["project_root_source"] == "cwd"
assert details["git_common_dir"] == "unknown"
assert "FIREBREAK_TASK_STATE_DIR" in details["ignored_keys"]
PY

printf '%s\n' "Firebreak project-config and doctor smoke test passed"
