#!/usr/bin/env bash
set -eu

repo_root=@REPO_ROOT@
if ! [ -f "$repo_root/flake.nix" ]; then
  echo "project-config smoke could not resolve the Firebreak source root" >&2
  exit 1
fi

if [ -n "${FIREBREAK_TMPDIR:-}" ]; then
  firebreak_tmp_root=$FIREBREAK_TMPDIR
elif [ -n "${XDG_CACHE_HOME:-}" ]; then
  firebreak_tmp_root=$XDG_CACHE_HOME/firebreak/tmp
elif [ -n "${HOME:-}" ]; then
  firebreak_tmp_root=$HOME/.cache/firebreak/tmp
else
  firebreak_tmp_root=${TMPDIR:-/tmp}/firebreak/tmp
fi
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-project-config.XXXXXX")
trap 'chmod -R u+w "$smoke_tmp_dir" 2>/dev/null || true; rm -rf "$smoke_tmp_dir"' EXIT INT TERM

project_dir=$smoke_tmp_dir/project
git_repo_dir=$smoke_tmp_dir/git-repo
mkdir -p "$project_dir"

state_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
    return 0
  fi

  printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
}

workspace_state_key=$(state_sha256 "$project_dir")
workspace_state_key=$(printf '%.16s' "$workspace_state_key")
expected_workspace_state_path="$HOME/shared-state-root/workspaces/$workspace_state_key/codex"

unset FIREBREAK_STATE_MODE
unset FIREBREAK_STATE_ROOT
unset FIREBREAK_PROJECT_CONFIG_FILE
unset FIREBREAK_LAUNCH_MODE
unset FIREBREAK_WORKER_MODE
unset FIREBREAK_WORKER_MODES
unset CODEX_STATE_MODE
unset CLAUDE_STATE_MODE

firebreak_cmd() {
  (
    cd "$project_dir"
    nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- "$@"
  )
}

prepare_git_repo() {
  mkdir -p "$git_repo_dir"
  cp -R "$repo_root/." "$git_repo_dir"
  rm -rf "$git_repo_dir/.git"
  chmod -R u+w "$git_repo_dir"
  (
    cd "$git_repo_dir"
    git init -q
    git config user.email smoke@example.invalid
    git config user.name "Firebreak Smoke"
    git add -A
    git commit -q -m "smoke"
  )
}

exact_firebreak_cmd() {
  (
    cd "$git_repo_dir"
    nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak -- "$@"
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
require_pattern "$init_template_stdout" "FIREBREAK_STATE_MODE=host" "default FIREBREAK_STATE_MODE template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_LAUNCH_MODE=run" "default FIREBREAK_LAUNCH_MODE template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_WORKER_MODE=local" "default FIREBREAK_WORKER_MODE template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_WORKER_MODES=codex=vm,claude=local" "default FIREBREAK_WORKER_MODES template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_CREDENTIAL_SLOT=default" "default FIREBREAK_CREDENTIAL_SLOT template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH=~/.firebreak/credentials" "default credential-slot root template entry"

set +e
interactive_init_output=$(
  printf '3\n1\n~/.firebreak\nn\nn\ny\n' | firebreak_cmd init 2>&1
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
require_pattern "$interactive_init_file" "FIREBREAK_STATE_MODE=host" "interactive init FIREBREAK_STATE_MODE entry"
require_pattern "$interactive_init_file" "FIREBREAK_LAUNCH_MODE=run" "interactive init FIREBREAK_LAUNCH_MODE entry"

cat >"$project_dir/.firebreak.env" <<EOF
FIREBREAK_STATE_MODE=host
FIREBREAK_STATE_ROOT=~/shared-state-root
CODEX_STATE_MODE=workspace
FIREBREAK_CREDENTIAL_SLOT=default
CODEX_CREDENTIAL_SLOT=backup
FIREBREAK_TASK_STATE_DIR=/tmp/internal-only
EOF

doctor_output=$(FIREBREAK_STATE_MODE=vm firebreak_cmd doctor)
require_pattern "$doctor_output" "codex_state" "doctor codex summary"
require_pattern "$doctor_output" "workspace ($expected_workspace_state_path)" "Codex-specific state precedence"
require_pattern "$doctor_output" "claude_state" "doctor claude summary"
require_pattern "$doctor_output" "vm (/home/dev/.firebreak/claude)" "environment overrides project file for generic state mode"
require_pattern "$doctor_output" "codex_credentials" "doctor codex credential summary"
require_pattern "$doctor_output" "backup ($HOME/.firebreak/credentials/backup/codex)" "Codex-specific credential slot precedence"
require_pattern "$doctor_output" "claude_credentials" "doctor claude credential summary"
require_pattern "$doctor_output" "default ($HOME/.firebreak/credentials/default/claude)" "default credential slot fallback"
require_pattern "$doctor_output" "Remove unsupported keys from .firebreak.env" "doctor unsupported-key guidance"
require_pattern "$doctor_output" "cwd_whitespace" "doctor cwd compatibility reporting"

doctor_verbose_output=$(FIREBREAK_STATE_MODE=vm firebreak_cmd doctor --verbose)
require_pattern "$doctor_verbose_output" "Details" "doctor verbose details header"
require_pattern "$doctor_verbose_output" "project_root_source" "doctor verbose project root source"
require_pattern "$doctor_verbose_output" "git_common_dir" "doctor verbose git common dir"

doctor_json=$(FIREBREAK_STATE_MODE=vm firebreak_cmd doctor --json)
DOCTOR_JSON=$doctor_json PROJECT_DIR=$project_dir WORKSPACE_STATE_KEY=$workspace_state_key python3 - <<'PY'
import json
import os
import sys

obj = json.loads(os.environ["DOCTOR_JSON"])
project_dir = os.environ["PROJECT_DIR"]
workspace_state_key = os.environ["WORKSPACE_STATE_KEY"]

assert obj["project_config_source"] == "project-default"
assert "FIREBREAK_TASK_STATE_DIR" in obj["ignored_config_keys"]
assert obj["tools"]["codex"]["mode"] == "workspace"
assert obj["tools"]["codex"]["path"] == os.path.expanduser(f"~/shared-state-root/workspaces/{workspace_state_key}/codex")
assert obj["tools"]["codex"]["credential_slot"] == "backup"
assert obj["tools"]["codex"]["credential_path"] == os.path.expanduser("~/.firebreak/credentials/backup/codex")
assert obj["tools"]["claude-code"]["mode"] == "vm"
assert obj["tools"]["claude-code"]["credential_slot"] == "default"
assert obj["tools"]["claude-code"]["credential_path"] == os.path.expanduser("~/.firebreak/credentials/default/claude")
assert obj["launch_mode"] == "run"
PY

doctor_verbose_json=$(FIREBREAK_STATE_MODE=vm firebreak_cmd doctor --verbose --json)
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

prepare_git_repo

exact_doctor_json=$(exact_firebreak_cmd doctor --json)
EXACT_DOCTOR_JSON=$exact_doctor_json GIT_REPO_DIR=$git_repo_dir python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["EXACT_DOCTOR_JSON"])
git_repo_dir = os.environ["GIT_REPO_DIR"]

assert obj["project_root"] == git_repo_dir
assert obj["cwd"] == git_repo_dir
assert obj["project_config_source"] == "none"
PY

exact_worker_state_dir=$smoke_tmp_dir/exact-worker-state
mkdir -p "$exact_worker_state_dir"
exact_worker_debug_json=$(
  FIREBREAK_WORKER_STATE_DIR="$exact_worker_state_dir" \
    exact_firebreak_cmd worker debug --json
)
EXACT_WORKER_DEBUG_JSON=$exact_worker_debug_json EXACT_WORKER_STATE_DIR=$exact_worker_state_dir python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["EXACT_WORKER_DEBUG_JSON"])

assert obj["authority"] == "host"
assert obj["state_dir"] == os.environ["EXACT_WORKER_STATE_DIR"]
assert obj["worker_count"] == 0
assert obj["requests"] == []
PY

printf '%s\n' "Firebreak project-config and doctor smoke test passed"
