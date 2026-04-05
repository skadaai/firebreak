#!/usr/bin/env bash
set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-credential-slots.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

credential_root=$smoke_tmp_dir/credentials
workspace_dir=$smoke_tmp_dir/workspace
mkdir -p \
  "$credential_root/default/credential-fixture" \
  "$credential_root/default/credential-fixture-peer" \
  "$credential_root/alternate/credential-fixture-peer" \
  "$workspace_dir"

require_pattern() {
  haystack=$1
  pattern=$2
  description=$3

  if ! printf '%s\n' "$haystack" | grep -F -q "$pattern"; then
    printf '%s\n' "$haystack" >&2
    printf '%s\n' "missing $description: $pattern" >&2
    exit 1
  fi
}

state_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    return
  fi

  echo "missing sha256sum/shasum" >&2
  exit 1
}

cat >"$credential_root/default/credential-fixture/auth.json" <<'EOF'
default-auth
EOF
cat >"$credential_root/default/credential-fixture/FIXTURE_API_KEY" <<'EOF'
default-api-key
EOF
cat >"$credential_root/default/credential-fixture/FIXTURE_HELPER_KEY" <<'EOF'
default-helper-key
EOF

cat >"$credential_root/default/credential-fixture-peer/auth.json" <<'EOF'
peer-default-auth
EOF
cat >"$credential_root/default/credential-fixture-peer/FIXTURE_API_KEY" <<'EOF'
peer-default-api-key
EOF
cat >"$credential_root/default/credential-fixture-peer/FIXTURE_HELPER_KEY" <<'EOF'
peer-default-helper-key
EOF

cat >"$credential_root/alternate/credential-fixture-peer/auth.json" <<'EOF'
peer-alt-auth
EOF
cat >"$credential_root/alternate/credential-fixture-peer/FIXTURE_API_KEY" <<'EOF'
peer-alt-api-key
EOF
cat >"$credential_root/alternate/credential-fixture-peer/FIXTURE_HELPER_KEY" <<'EOF'
peer-alt-helper-key
EOF

(
  cd "$workspace_dir"
  git init -q
)
project_key=$(state_sha256 "$workspace_dir")
project_key=$(printf '%.16s' "$project_key")
expected_workspace_root="/run/firebreak-state-root/workspaces/$project_key"

run_fixture() {
  env \
    -u FIREBREAK_STATE_ROOT \
    -u FIXTURE_STATE_MODE \
    -u FIXTURE_CREDENTIAL_SLOT \
    -u PEER_CREDENTIAL_SLOT \
    -u CODEX_STATE_MODE \
    -u CLAUDE_STATE_MODE \
    FIREBREAK_INSTANCE_EPHEMERAL=1 \
    FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$credential_root" \
    FIREBREAK_STATE_MODE=workspace \
    FIREBREAK_CREDENTIAL_SLOT=default \
    "$@"
}

status_output=$(
  cd "$workspace_dir"
  run_fixture @FIXTURE_PACKAGE_BIN@ status
)
require_pattern "$status_output" "FIXTURE_NAME=credential-fixture" "primary fixture name"
require_pattern "$status_output" "FIXTURE_HOME=$expected_workspace_root/credential-fixture" "workspace state root"
require_pattern "$status_output" "AUTH_JSON=default-auth" "file binding content"
require_pattern "$status_output" "API_KEY=default-api-key" "env binding content"
require_pattern "$status_output" "HELPER_VALUE=default-helper-key" "helper binding content"
if [ -e "$workspace_dir/.firebreak/credential-fixture" ]; then
  echo "credential-slot smoke should not create a project-local Firebreak config overlay" >&2
  exit 1
fi

rotate_output=$(
  cd "$workspace_dir"
  run_fixture @FIXTURE_PACKAGE_BIN@ rotate-auth rotated-auth
)
require_pattern "$rotate_output" "ROTATED_HOME=$expected_workspace_root/credential-fixture" "rotated workspace state root"
if [ "$(cat "$credential_root/default/credential-fixture/auth.json")" != "rotated-auth" ]; then
  echo "credential-slot smoke did not sync rotated auth back into the selected slot" >&2
  exit 1
fi

login_output=$(
  cd "$workspace_dir"
  run_fixture \
    FIXTURE_CREDENTIAL_SLOT=login-slot \
    @FIXTURE_PACKAGE_BIN@ login direct-login-auth
)
require_pattern "$login_output" "LOGIN_HOME=/run/credential-slots-host-root/login-slot/credential-fixture" "slot-root login materialization"
if [ "$(cat "$credential_root/login-slot/credential-fixture/auth.json")" != "direct-login-auth" ]; then
  echo "credential-slot smoke did not write the login result into the selected slot" >&2
  exit 1
fi

multi_tool_output=$(
  cd "$workspace_dir"
  run_fixture \
    PEER_CREDENTIAL_SLOT=alternate \
    AGENT_VM_COMMAND='credential-fixture status && credential-fixture-peer status' \
    FIREBREAK_LAUNCH_MODE=shell \
    @FIXTURE_PACKAGE_BIN@
)
require_pattern "$multi_tool_output" "FIXTURE_NAME=credential-fixture" "multi-tool default fixture output"
require_pattern "$multi_tool_output" "API_KEY=default-api-key" "multi-tool default slot API key"
require_pattern "$multi_tool_output" "HELPER_VALUE=default-helper-key" "multi-tool default slot helper"
require_pattern "$multi_tool_output" "FIXTURE_NAME=credential-fixture-peer" "multi-tool peer fixture output"
require_pattern "$multi_tool_output" "AUTH_JSON=peer-alt-auth" "multi-tool override file binding"
require_pattern "$multi_tool_output" "API_KEY=peer-alt-api-key" "multi-tool override env binding"
require_pattern "$multi_tool_output" "HELPER_VALUE=peer-alt-helper-key" "multi-tool override helper binding"

printf '%s\n' "Firebreak credential-slot smoke test passed"
