#!/usr/bin/env bash
set -eu

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$repo_root/modules/base/host/firebreak-project-config.sh"

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-agent-version.XXXXXX")
runtime_root=$smoke_tmp_dir/runtime
runtime_dir=""

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    echo "@AGENT_DISPLAY_NAME@ version smoke preserved artifacts under: $smoke_tmp_dir" >&2
    if [ -n "$runtime_dir" ] && [ -d "$runtime_dir" ]; then
      echo "@AGENT_DISPLAY_NAME@ version smoke preserved runtime dir: $runtime_dir" >&2
    fi
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

run_with_clean_firebreak_env() (
  while IFS= read -r env_key; do
    [ -n "$env_key" ] || continue
    unset "$env_key"
  done <<EOF
$(firebreak_list_scrubbable_env_keys)
EOF

  while [ "$#" -gt 0 ]; do
    case "$1" in
      *=*)
        assignment=$1
        export "${assignment%%=*}=${assignment#*=}"
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  exec "$@"
)

output=$(
  run_with_clean_firebreak_env \
    FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
    FIREBREAK_INSTANCE_EPHEMERAL=1 \
    FIREBREAK_TMPDIR="$runtime_root" \
    @AGENT_PACKAGE_BIN@ --version 2>&1
)

case "$output" in
  *[0-9].[0-9]* | *[0-9].[0-9].[0-9]*)
    ;;
  *)
    printf '%s\n' "$output" >&2
    echo "@AGENT_DISPLAY_NAME@ version smoke did not print a recognizable version string" >&2
    exit 1
    ;;
esac

runtime_dir=$(printf '%s\n' "$output" | sed -n 's/^keeping Firebreak runtime directory: //p' | tail -n 1)
if [ -z "$runtime_dir" ] || ! [ -d "$runtime_dir" ]; then
  printf '%s\n' "$output" >&2
  echo "@AGENT_DISPLAY_NAME@ version smoke did not preserve a reviewable runtime dir" >&2
  exit 1
fi

bootstrap_state_path=$runtime_dir/o/bootstrap-state.json
if ! [ -f "$bootstrap_state_path" ]; then
  find "$runtime_dir" -maxdepth 2 -type f -print >&2 || true
  echo "@AGENT_DISPLAY_NAME@ version smoke did not expose bootstrap-state.json" >&2
  exit 1
fi

command_state_path=$runtime_dir/o/command-state.json
if ! [ -f "$command_state_path" ]; then
  find "$runtime_dir" -maxdepth 2 -type f -print >&2 || true
  echo "@AGENT_DISPLAY_NAME@ version smoke did not expose command-state.json" >&2
  exit 1
fi

if ! grep -F -q '"phase": "wrapper-ready"' "$bootstrap_state_path"; then
  cat "$bootstrap_state_path" >&2
  echo "@AGENT_DISPLAY_NAME@ version smoke did not report wrapper-ready bootstrap state" >&2
  exit 1
fi

if ! grep -F -q '"phase": "command-exit"' "$command_state_path"; then
  cat "$command_state_path" >&2
  echo "@AGENT_DISPLAY_NAME@ version smoke did not report command-exit command state" >&2
  exit 1
fi

printf '%s\n' "$output"
