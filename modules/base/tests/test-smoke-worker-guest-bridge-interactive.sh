set -eu

default_firebreak_tmpdir=${TMPDIR:-/tmp}
if [ -d /cache ] && [ -w /cache ]; then
  default_firebreak_tmpdir=/cache/firebreak
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-$default_firebreak_tmpdir}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-guest-bridge-interactive.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

workspace_dir=$smoke_tmp_dir/workspace
mkdir -p "$workspace_dir"

guest_script=$workspace_dir/guest-bridge-interactive-check.sh
cat >"$guest_script" <<'EOF'
set -eu

attach_output=$(
  cd "$PWD"
  printf 'ping\n' |
    script -qefc "firebreak worker run --kind bridge-interactive-firebreak --workspace '$PWD' --attach --" /dev/null
)

printf '__BRIDGE_INTERACTIVE_ATTACH__%s\n' "$attach_output"

if ! printf '%s\n' "$attach_output" | grep -F -q 'READY'; then
  printf '%s\n' "$attach_output" >&2
  echo "interactive guest bridge smoke did not receive the ready marker" >&2
  exit 1
fi

if ! printf '%s\n' "$attach_output" | grep -F -q 'ECHO:ping'; then
  printf '%s\n' "$attach_output" >&2
  echo "interactive guest bridge smoke did not receive the echoed input" >&2
  exit 1
fi

printf '%s\n' '__BRIDGE_INTERACTIVE_OK__'
EOF

output=$(
  cd "$workspace_dir"
  env -u AGENT_CONFIG -u AGENT_CONFIG_HOST_PATH -u CODEX_CONFIG -u CODEX_CONFIG_HOST_PATH -u CLAUDE_CONFIG -u CLAUDE_CONFIG_HOST_PATH \
    FIREBREAK_INSTANCE_EPHEMERAL=1 @BRIDGE_VM_BIN@ "$guest_script"
)

if ! printf '%s\n' "$output" | grep -F -q '__BRIDGE_INTERACTIVE_OK__'; then
  printf '%s\n' "$output" >&2
  echo "worker guest bridge interactive smoke did not complete successfully" >&2
  exit 1
fi

printf '%s\n' "Firebreak worker guest bridge interactive smoke test passed"
