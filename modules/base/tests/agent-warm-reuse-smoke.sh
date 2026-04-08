#!/usr/bin/env bash
set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this warm reuse smoke test from inside the Firebreak repository" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$repo_root/modules/base/host/firebreak-project-config.sh"

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-agent-warm-reuse.XXXXXX")
workspace_dir=$smoke_tmp_dir/workspace
state_root=$smoke_tmp_dir/state
firebreak_state_dir=$state_root
instance_dir=""
controller_pid=""

cleanup() {
  status=$?
  trap - EXIT INT TERM

  if [ -n "$controller_pid" ]; then
    kill "$controller_pid" 2>/dev/null || true
  fi

  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    echo "@AGENT_DISPLAY_NAME@ warm reuse smoke preserved artifacts under: $smoke_tmp_dir" >&2
    if [ -n "$instance_dir" ] && [ -d "$instance_dir" ]; then
      echo "@AGENT_DISPLAY_NAME@ warm reuse smoke preserved instance dir: $instance_dir" >&2
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

require_version_output() {
  output=$1
  case "$output" in
    *[0-9].[0-9]* | *[0-9].[0-9].[0-9]*)
      ;;
    *)
      printf '%s\n' "$output" >&2
      echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not print a recognizable version string" >&2
      exit 1
      ;;
  esac
}

run_version_command() {
  (
    cd "$workspace_dir"
    run_with_clean_firebreak_env \
      FIREBREAK_STATE_ROOT="$state_root" \
      FIREBREAK_STATE_DIR="$firebreak_state_dir" \
      FIREBREAK_DEBUG_KEEP_RUNTIME=0 \
      @AGENT_PACKAGE_BIN@ --version 2>&1
  )
}

read_json_field() {
  json_path=$1
  field_name=$2
  python3 - "$json_path" "$field_name" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

value = payload.get(sys.argv[2], "")
print(value if isinstance(value, str) else "")
PY
}

mkdir -p "$workspace_dir" "$state_root/instances"

first_output=$(run_version_command)
require_version_output "$first_output"

instance_dir=$(find "$state_root/instances" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -z "$instance_dir" ] || ! [ -d "$instance_dir" ]; then
  find "$state_root" -maxdepth 3 -print >&2 || true
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not create a stable instance dir" >&2
  exit 1
fi

controller_state_dir=$instance_dir/.firebreak-local
controller_pid_file=$controller_state_dir/daemon.pid
controller_runtime_dir_file=$controller_state_dir/runtime-dir

if ! [ -r "$controller_pid_file" ] || ! [ -r "$controller_runtime_dir_file" ]; then
  find "$instance_dir" -maxdepth 3 -print >&2 || true
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not record controller state" >&2
  exit 1
fi

controller_pid=$(cat "$controller_pid_file")
runtime_dir_first=$(cat "$controller_runtime_dir_file")
if ! kill -0 "$controller_pid" 2>/dev/null; then
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke found a dead controller pid after the first run" >&2
  exit 1
fi

if ! [ -d "$runtime_dir_first/o" ] || ! [ -f "$runtime_dir_first/o/command-agent-ready" ]; then
  find "$runtime_dir_first" -maxdepth 3 -print >&2 || true
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not preserve a ready command-agent runtime" >&2
  exit 1
fi

request_id_first=$(read_json_field "$runtime_dir_first/o/request.json" "request_id")
if [ -z "$request_id_first" ]; then
  cat "$runtime_dir_first/o/request.json" >&2 || true
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not capture the first request id" >&2
  exit 1
fi

second_output=$(run_version_command)
require_version_output "$second_output"

controller_pid_second=$(cat "$controller_pid_file")
runtime_dir_second=$(cat "$controller_runtime_dir_file")
if [ "$controller_pid_second" != "$controller_pid" ]; then
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke respawned the controller instead of reusing it" >&2
  exit 1
fi

if [ "$runtime_dir_second" != "$runtime_dir_first" ]; then
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke replaced the controller runtime instead of reusing it" >&2
  exit 1
fi

if ! kill -0 "$controller_pid_second" 2>/dev/null; then
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke found a dead controller pid after the second run" >&2
  exit 1
fi

request_id_second=$(read_json_field "$runtime_dir_second/o/request.json" "request_id")
if [ -z "$request_id_second" ] || [ "$request_id_second" = "$request_id_first" ]; then
  cat "$runtime_dir_second/o/request.json" >&2 || true
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not record a distinct second request id" >&2
  exit 1
fi

command_state_path=$runtime_dir_second/o/command-state.json
if ! [ -f "$command_state_path" ] || ! grep -F -q "\"request_id\": \"$request_id_second\"" "$command_state_path"; then
  cat "$command_state_path" >&2 || true
  echo "@AGENT_DISPLAY_NAME@ warm reuse smoke did not persist the second command state" >&2
  exit 1
fi

printf '%s\n' "first-run: $first_output"
printf '%s\n' "second-run: $second_output"
printf '%s\n' "@AGENT_DISPLAY_NAME@ warm reuse smoke test passed"
