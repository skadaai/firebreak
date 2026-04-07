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
require_pattern "$init_template_stdout" "# FIREBREAK_ENVIRONMENT_MODE=auto" "default FIREBREAK_ENVIRONMENT_MODE template entry"
require_pattern "$init_template_stdout" "# FIREBREAK_ENVIRONMENT_INSTALLABLE=.#devShells.x86_64-linux.default" "default FIREBREAK_ENVIRONMENT_INSTALLABLE template entry"
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
require_pattern "$doctor_output" "environment" "doctor environment summary"
require_pattern "$doctor_output" "package-only/none" "doctor default environment source summary"
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
assert obj["environment"]["source"] == "package-only"
assert obj["environment"]["kind"] == "none"
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
assert details["environment_identity"]
assert details["environment_cache_dir"]
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

environment_flake_dir=$smoke_tmp_dir/environment-flake
mkdir -p "$environment_flake_dir"
cat >"$environment_flake_dir/flake.nix" <<EOF
{
  description = "firebreak environment smoke";
  inputs.firebreak.url = "path:$repo_root";
  inputs.nixpkgs.follows = "firebreak/nixpkgs";
  outputs = { self, nixpkgs, firebreak }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.\${system}.default = pkgs.mkShell {
        packages = [ pkgs.hello pkgs.ripgrep ];
        FOO = "bar";
      };
      packages.\${system}.default = pkgs.hello;
    };
}
EOF

environment_cmd() {
  (
    cd "$environment_flake_dir"
    nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- "$@"
  )
}

environment_resolve_json=$(
  FIREBREAK_ENVIRONMENT_MODE=devshell \
    FIREBREAK_ENVIRONMENT_INSTALLABLE=.#devShells.x86_64-linux.default \
    environment_cmd environment resolve --json
)
ENVIRONMENT_RESOLVE_JSON=$environment_resolve_json python3 - <<'PY'
import json
import os
from pathlib import Path

obj = json.loads(os.environ["ENVIRONMENT_RESOLVE_JSON"])

assert obj["source"] == "explicit"
assert obj["kind"] == "devshell"
assert obj["installable"].endswith("#devShells.x86_64-linux.default")
assert obj["identity"]
assert Path(obj["cache_dir"]).is_dir()
assert Path(obj["env_file"]).is_file()
PY

environment_resolve_json_second=$(
  FIREBREAK_ENVIRONMENT_MODE=devshell \
    FIREBREAK_ENVIRONMENT_INSTALLABLE=.#devShells.x86_64-linux.default \
    environment_cmd environment resolve --json
)
ENVIRONMENT_RESOLVE_JSON_SECOND=$environment_resolve_json_second python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["ENVIRONMENT_RESOLVE_JSON_SECOND"])
assert obj["reused"] is True
PY

if [ -e "$environment_flake_dir/flake.lock" ]; then
  echo "environment resolve should not write flake.lock into the project workspace" >&2
  exit 1
fi

environment_env_file=$(ENVIRONMENT_RESOLVE_JSON=$environment_resolve_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["ENVIRONMENT_RESOLVE_JSON"])
print(obj["env_file"])
PY
)

FOO_VALUE=$(
  ENVIRONMENT_ENV_FILE=$environment_env_file bash -lc '
    set -eu
    . "$ENVIRONMENT_ENV_FILE"
    command -v hello >/dev/null 2>&1
    command -v rg >/dev/null 2>&1
    printf "%s\n" "$FOO"
  '
)
if [ "$FOO_VALUE" != "bar" ]; then
  echo "environment resolve smoke did not propagate FOO from devShell" >&2
  exit 1
fi

package_environment_json=$(
  FIREBREAK_PACKAGE_IDENTITY=package-smoke \
    FIREBREAK_PACKAGE_ENVIRONMENT_INSTALLABLES_JSON='["nixpkgs#jq"]' \
    environment_cmd environment resolve --json
)
PACKAGE_ENVIRONMENT_JSON=$package_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["PACKAGE_ENVIRONMENT_JSON"])

assert obj["source"] == "package-only"
assert obj["kind"] == "none"
assert json.loads(obj["package_installables_json"]) == ["nixpkgs#jq"]
assert obj["identity"]
assert obj["env_file"]
PY

package_environment_env_file=$(PACKAGE_ENVIRONMENT_JSON=$package_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["PACKAGE_ENVIRONMENT_JSON"])
print(obj["env_file"])
PY
)

PACKAGE_ENVIRONMENT_ENV_FILE=$package_environment_env_file bash -lc '
  set -eu
  export PATH=/usr/bin:/bin
  . "$PACKAGE_ENVIRONMENT_ENV_FILE"
  command -v jq >/dev/null 2>&1
'

jq_store_path=$(nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw nixpkgs#jq.outPath)
package_path_environment_json=$(
  FIREBREAK_PACKAGE_IDENTITY=package-path-smoke \
    FIREBREAK_PACKAGE_ENVIRONMENT_PATHS_JSON="[\"$jq_store_path/bin\"]" \
    FIREBREAK_PACKAGE_ENVIRONMENT_EXPORTS_JSON='{"FIREBREAK_TEST_OVERLAY":"1"}' \
    environment_cmd environment resolve --json
)
PACKAGE_PATH_ENVIRONMENT_JSON=$package_path_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["PACKAGE_PATH_ENVIRONMENT_JSON"])

assert obj["source"] == "package-only"
assert obj["kind"] == "none"
assert obj["identity"]
assert obj["env_file"]
PY

package_path_environment_env_file=$(PACKAGE_PATH_ENVIRONMENT_JSON=$package_path_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["PACKAGE_PATH_ENVIRONMENT_JSON"])
print(obj["env_file"])
PY
)

PACKAGE_PATH_ENVIRONMENT_ENV_FILE=$package_path_environment_env_file bash -lc '
  set -eu
  export PATH=/usr/bin:/bin
  . "$PACKAGE_PATH_ENVIRONMENT_ENV_FILE"
  command -v jq >/dev/null 2>&1
  [ "$FIREBREAK_TEST_OVERLAY" = "1" ]
'

environment_auto_json=$(
  FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED=1 \
    environment_cmd environment resolve --json
)
ENVIRONMENT_AUTO_JSON=$environment_auto_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["ENVIRONMENT_AUTO_JSON"])

assert obj["source"] == "project-nix"
assert obj["kind"] == "devshell"
assert obj["project_nix_enabled"] is True
assert obj["project_nix_source"] == "devShells.x86_64-linux.default"
PY

unsupported_environment_flake_dir=$smoke_tmp_dir/unsupported-environment-flake
mkdir -p "$unsupported_environment_flake_dir"
cat >"$unsupported_environment_flake_dir/flake.nix" <<EOF
{
  description = "firebreak unsupported environment smoke";
  inputs.firebreak.url = "path:$repo_root";
  inputs.nixpkgs.follows = "firebreak/nixpkgs";
  outputs = { self, nixpkgs, firebreak }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.\${system}.demo = pkgs.hello;
    };
}
EOF

set +e
unsupported_environment_output=$(
  (
    cd "$unsupported_environment_flake_dir"
    FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED=1 \
      nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- environment resolve --json
  ) 2>&1
)
unsupported_environment_status=$?
set -e

if [ "$unsupported_environment_status" -eq 0 ]; then
  printf '%s\n' "$unsupported_environment_output" >&2
  echo "unsupported project-local environment should fail fast" >&2
  exit 1
fi

require_pattern "$unsupported_environment_output" \
  "could not map path:" \
  "unsupported project-local environment failure"
require_pattern "$unsupported_environment_output" \
  "devShells.x86_64-linux.default, packages.x86_64-linux.default, or legacyPackages.x86_64-linux.default" \
  "supported default workspace environment guidance"

legacy_environment_flake_dir=$smoke_tmp_dir/legacy-environment-flake
mkdir -p "$legacy_environment_flake_dir"
cat >"$legacy_environment_flake_dir/flake.nix" <<EOF
{
  description = "firebreak legacyPackages environment smoke";
  inputs.firebreak.url = "path:$repo_root";
  inputs.nixpkgs.follows = "firebreak/nixpkgs";
  outputs = { self, nixpkgs, firebreak }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      legacyPackages.\${system}.default = pkgs.hello;
    };
}
EOF

legacy_environment_json=$(
  (
    cd "$legacy_environment_flake_dir"
    FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED=1 \
      nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- environment resolve --json
  )
)
LEGACY_ENVIRONMENT_JSON=$legacy_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["LEGACY_ENVIRONMENT_JSON"])

assert obj["source"] == "project-nix"
assert obj["kind"] == "package"
assert obj["project_nix_enabled"] is True
assert obj["project_nix_source"] == "legacyPackages.x86_64-linux.default"
assert obj["installable"].endswith("#legacyPackages.x86_64-linux.default")
PY

shell_file_environment_dir=$smoke_tmp_dir/shell-file-environment
mkdir -p "$shell_file_environment_dir"
cat >"$shell_file_environment_dir/shell.nix" <<'EOF'
with import <nixpkgs> {};
mkShell {
  packages = [ hello ];
  FOO = "shell";
}
EOF
cat >"$shell_file_environment_dir/default.nix" <<'EOF'
with import <nixpkgs> {};
mkShell {
  packages = [ hello ];
  FOO = "default";
}
EOF

shell_file_environment_json=$(
  (
    cd "$shell_file_environment_dir"
    FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED=1 \
      nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- environment resolve --json
  )
)
SHELL_FILE_ENVIRONMENT_JSON=$shell_file_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["SHELL_FILE_ENVIRONMENT_JSON"])

assert obj["source"] == "project-nix"
assert obj["kind"] == "devshell"
assert obj["project_nix_enabled"] is True
assert obj["project_nix_source"] == "shell.nix"
assert obj["project_nix_file"].endswith("/shell.nix")
assert obj["project_lock_hash"]
assert obj["installable"].startswith("file:")
PY

shell_file_environment_env_file=$(SHELL_FILE_ENVIRONMENT_JSON=$shell_file_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["SHELL_FILE_ENVIRONMENT_JSON"])
print(obj["env_file"])
PY
)

SHELL_FILE_ENVIRONMENT_ENV_FILE=$shell_file_environment_env_file bash -lc '
  set -eu
  export PATH=/usr/bin:/bin
  . "$SHELL_FILE_ENVIRONMENT_ENV_FILE"
  command -v hello >/dev/null 2>&1
  [ "$FOO" = "shell" ]
'

default_file_environment_dir=$smoke_tmp_dir/default-file-environment
mkdir -p "$default_file_environment_dir"
cat >"$default_file_environment_dir/default.nix" <<'EOF'
with import <nixpkgs> {};
mkShell {
  packages = [ hello ];
  FOO = "default-only";
}
EOF

default_file_environment_json=$(
  (
    cd "$default_file_environment_dir"
    FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED=1 \
      nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- environment resolve --json
  )
)
DEFAULT_FILE_ENVIRONMENT_JSON=$default_file_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["DEFAULT_FILE_ENVIRONMENT_JSON"])

assert obj["source"] == "project-nix"
assert obj["kind"] == "devshell"
assert obj["project_nix_enabled"] is True
assert obj["project_nix_source"] == "default.nix"
assert obj["project_nix_file"].endswith("/default.nix")
assert obj["project_lock_hash"]
assert obj["installable"].startswith("file:")
PY

default_file_environment_env_file=$(DEFAULT_FILE_ENVIRONMENT_JSON=$default_file_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["DEFAULT_FILE_ENVIRONMENT_JSON"])
print(obj["env_file"])
PY
)

DEFAULT_FILE_ENVIRONMENT_ENV_FILE=$default_file_environment_env_file bash -lc '
  set -eu
  export PATH=/usr/bin:/bin
  . "$DEFAULT_FILE_ENVIRONMENT_ENV_FILE"
  command -v hello >/dev/null 2>&1
  [ "$FOO" = "default-only" ]
'

explicit_file_environment_json=$(
  (
    cd "$default_file_environment_dir"
    FIREBREAK_ENVIRONMENT_MODE=devshell \
      FIREBREAK_ENVIRONMENT_INSTALLABLE=./default.nix \
      nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run "path:$repo_root#firebreak" -- environment resolve --json
  )
)
EXPLICIT_FILE_ENVIRONMENT_JSON=$explicit_file_environment_json python3 - <<'PY'
import json
import os

obj = json.loads(os.environ["EXPLICIT_FILE_ENVIRONMENT_JSON"])

assert obj["source"] == "explicit"
assert obj["kind"] == "devshell"
assert obj["installable"].startswith("file:")
assert obj["installable"].endswith("/default.nix")
assert obj["project_nix_file"].endswith("/default.nix")
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
