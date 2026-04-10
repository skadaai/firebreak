set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$repo_root/modules/base/host/firebreak-project-config.sh"

host_uid=$(id -u)
host_gid=$(id -g)
timeout_seconds=${FIREBREAK_SMOKE_TIMEOUT:-${CODEX_VM_SMOKE_TIMEOUT:-900}}
firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
host_state_dir=$(mktemp -d "$firebreak_tmp_root/tool-smoke-state.XXXXXX")
host_state_root=$(mktemp -d "$firebreak_tmp_root/tool-smoke-state-root.XXXXXX")

state_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
    return 0
  fi

  printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
}

workspace_state_key=$(state_sha256 "$repo_root")
workspace_state_key=$(printf '%.16s' "$workspace_state_key")
expected_workspace_state_dir="/run/firebreak-state-root/workspaces/$workspace_state_key/@STATE_SUBDIR@"

cleanup() {
  rm -rf "$host_state_dir"
  rm -rf "$host_state_root"
}
trap cleanup EXIT INT TERM

printf '%s\n' "host-smoke-marker" > "$host_state_dir/marker.txt"
ln -s "$host_state_dir" "$host_state_root/@STATE_SUBDIR@"

smoke_probe_command=$(cat <<'EOF'
printf '__SMOKE_PWD__%s\n' "$PWD"
printf '__SMOKE_IDS__%s:%s\n' "$(id -u)" "$(id -g)"
printf '__SMOKE_OWNER__%s\n' "$(stat -c %u:%g .)"
printf '__SMOKE_STATE_DIR__%s\n' "${FIREBREAK_TOOL_STATE_DIR:-}"
test -f flake.nix
printf '__SMOKE_FLAKE__ok\n'
test -d "$FIREBREAK_TOOL_STATE_DIR"
test -w "$FIREBREAK_TOOL_STATE_DIR"
printf '__SMOKE_STATE_OK__ok\n'
if [ "$FIREBREAK_TOOL_STATE_DIR" = "/run/firebreak-state-root/@STATE_SUBDIR@" ]; then
  test -f "$FIREBREAK_TOOL_STATE_DIR/marker.txt"
  printf '__SMOKE_HOST_STATE__ok\n'
fi
@TOOL_BIN@ --version | sed -n '1s/^/__SMOKE_TOOL__/p'
EOF
)

cd "$repo_root"
run_flake=$repo_root/scripts/run-flake.sh

if ! [ -f "$run_flake" ]; then
  echo "missing flake runner helper: $run_flake" >&2
  exit 1
fi

require_line() {
  output=$1
  prefix=$2
  description=$3

  value=$(printf '%s\n' "$output" | sed -n "s/^${prefix}//p" | head -n 1)
  if [ -z "$value" ]; then
    printf '%s\n' "$output" >&2
    echo "missing $description in smoke output" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

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

run_scenario() {
  package_name=$1
  mode=$2
  expected_state_dir=$3
  scenario_label=$4
  host_state_path=${5-}

  printf '%s\n' "running: $scenario_label"

  set +e
  output=$(
    run_with_clean_firebreak_env \
      FIREBREAK_STATE_MODE="$mode" \
      FIREBREAK_LAUNCH_MODE=shell \
      FIREBREAK_INSTANCE_EPHEMERAL=1 \
      FIREBREAK_STATE_ROOT="${host_state_path:-}" \
      WORKLOAD_VM_COMMAND="$smoke_probe_command" \
      timeout --foreground "$timeout_seconds" \
      bash "$run_flake" run ".#$package_name" 2>&1
  )
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    echo "shell smoke scenario failed: $scenario_label" >&2
    exit 1
  fi

  guest_pwd=$(require_line "$output" '__SMOKE_PWD__' 'guest working directory')
  if [ "$guest_pwd" != "$repo_root" ]; then
    printf '%s\n' "$output" >&2
    echo "unexpected guest working directory: $guest_pwd" >&2
    exit 1
  fi

  guest_ids=$(require_line "$output" '__SMOKE_IDS__' 'guest uid/gid')
  if [ "$guest_ids" != "$host_uid:$host_gid" ]; then
    printf '%s\n' "$output" >&2
    echo "unexpected guest uid/gid: $guest_ids" >&2
    exit 1
  fi

  workspace_owner=$(require_line "$output" '__SMOKE_OWNER__' 'workspace ownership')
  if [ "$workspace_owner" != "$host_uid:$host_gid" ]; then
    printf '%s\n' "$output" >&2
    echo "unexpected workspace ownership: $workspace_owner" >&2
    exit 1
  fi

  tool_state_dir=$(require_line "$output" '__SMOKE_STATE_DIR__' 'tool state directory')
  if [ "$tool_state_dir" != "$expected_state_dir" ]; then
    printf '%s\n' "$output" >&2
    echo "unexpected tool state directory: $tool_state_dir" >&2
    exit 1
  fi

  require_line "$output" '__SMOKE_FLAKE__' 'workspace contents' >/dev/null
  require_line "$output" '__SMOKE_STATE_OK__' 'tool state usability' >/dev/null
  if [ "$expected_state_dir" = "/run/firebreak-state-root/@STATE_SUBDIR@" ]; then
    require_line "$output" '__SMOKE_HOST_STATE__' 'host state marker' >/dev/null
  fi
  require_line "$output" '__SMOKE_TOOL__' '@TOOL_DISPLAY_NAME@ CLI' >/dev/null

  printf '%s\n' "ok: $scenario_label"
}

run_tool_command_scenario() {
  mode=$1
  scenario_label=$2
  tool_cli_arg=$3

  printf '%s\n' "running: $scenario_label"
  set +e
  output=$(
    run_with_clean_firebreak_env \
      FIREBREAK_STATE_MODE="$mode" \
      FIREBREAK_INSTANCE_EPHEMERAL=1 \
      timeout --foreground "$timeout_seconds" \
      bash "$run_flake" run .#@WORKLOAD_PACKAGE@ -- "$tool_cli_arg" 2>&1
  )
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    echo "one-shot tool command failed for: $scenario_label" >&2
    exit 1
  fi

  case "$output" in
    *[0-9].[0-9]* | *[0-9].[0-9].[0-9]*)
      ;;
    *)
      printf '%s\n' "$output" >&2
      echo "one-shot tool command did not print a recognizable version string for: $scenario_label" >&2
      exit 1
      ;;
  esac

  printf '%s\n' "ok: $scenario_label"
}

state_dir_preexists=0
if [ -e "$repo_root/@STATE_DIR_NAME@" ]; then
  state_dir_preexists=1
fi

run_tool_command_scenario workspace "default tool entry runs @TOOL_BIN@ --version as a one-shot command" "--version"
run_scenario @WORKLOAD_PACKAGE@ workspace "$expected_workspace_state_dir" "shell override uses workspace state"
if [ "$state_dir_preexists" = "0" ] && [ -e "$repo_root/@STATE_DIR_NAME@" ]; then
  echo "workspace mode should not create a Firebreak-managed project state overlay: $repo_root/@STATE_DIR_NAME@" >&2
  exit 1
fi
run_scenario @WORKLOAD_PACKAGE@ vm "@VM_STATE_ROOT@/@STATE_DIR_NAME@" "shell override uses vm state"
run_scenario @WORKLOAD_PACKAGE@ host "/run/firebreak-state-root/@STATE_SUBDIR@" "shell override uses host state" "$host_state_root"

printf '%s\n' "Firebreak smoke test passed"
