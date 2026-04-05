set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

host_uid=$(id -u)
host_gid=$(id -g)
timeout_seconds=${FIREBREAK_SMOKE_TIMEOUT:-${CODEX_VM_SMOKE_TIMEOUT:-900}}
firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
host_config_dir=$(mktemp -d "$firebreak_tmp_root/agent-smoke-config.XXXXXX")
host_config_root=$(mktemp -d "$firebreak_tmp_root/agent-smoke-root.XXXXXX")

state_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
    return 0
  fi

  printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
}

workspace_state_key=$(state_sha256 "$repo_root")
workspace_state_key=$(printf '%.16s' "$workspace_state_key")
expected_workspace_config_dir="/run/firebreak-state-root/workspaces/$workspace_state_key/@STATE_SUBDIR@"

cleanup() {
  rm -rf "$host_config_dir"
  rm -rf "$host_config_root"
}
trap cleanup EXIT INT TERM

printf '%s\n' "host-smoke-marker" > "$host_config_dir/marker.txt"
mkdir -p "$host_config_root/@STATE_SUBDIR@"
cp "$host_config_dir/marker.txt" "$host_config_root/@STATE_SUBDIR@/marker.txt"

smoke_probe_command=$(cat <<'EOF'
printf '__SMOKE_PWD__%s\n' "$PWD"
printf '__SMOKE_IDS__%s:%s\n' "$(id -u)" "$(id -g)"
printf '__SMOKE_OWNER__%s\n' "$(stat -c %u:%g .)"
printf '__SMOKE_STATE_DIR__%s\n' "${FIREBREAK_TOOL_STATE_DIR:-}"
test -f flake.nix
printf '__SMOKE_FLAKE__ok\n'
test -d "$FIREBREAK_TOOL_STATE_DIR"
test -w "$FIREBREAK_TOOL_STATE_DIR"
printf '__SMOKE_CONFIG_OK__ok\n'
if [ "$FIREBREAK_TOOL_STATE_DIR" = "/run/firebreak-state-root/@STATE_SUBDIR@" ]; then
  test -f "$FIREBREAK_TOOL_STATE_DIR/marker.txt"
  printf '__SMOKE_HOST_CONFIG__ok\n'
fi
@AGENT_BIN@ --version | sed -n '1s/^/__SMOKE_AGENT__/p'
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
  while IFS='=' read -r env_key _; do
    case "$env_key" in
      FIREBREAK_STATE_MODE|FIREBREAK_STATE_ROOT|FIREBREAK_CREDENTIAL_SLOT|FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH|*_CREDENTIAL_SLOT)
        unset "$env_key"
        ;;
      *_STATE_MODE)
        case "$env_key" in
          NIX_CONFIG|FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG)
            ;;
          *)
            unset "$env_key"
            ;;
        esac
        ;;
    esac
  done <<EOF
$(env)
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
  expected_config_dir=$3
  scenario_label=$4
  host_config_path=${5-}

  printf '%s\n' "running: $scenario_label"

  set +e
  output=$(
    run_with_clean_firebreak_env \
      FIREBREAK_STATE_MODE="$mode" \
      FIREBREAK_LAUNCH_MODE=shell \
      FIREBREAK_INSTANCE_EPHEMERAL=1 \
      FIREBREAK_STATE_ROOT="${host_config_path:-}" \
      AGENT_VM_COMMAND="$smoke_probe_command" \
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
  if [ "$tool_state_dir" != "$expected_config_dir" ]; then
    printf '%s\n' "$output" >&2
    echo "unexpected tool state directory: $tool_state_dir" >&2
    exit 1
  fi

  require_line "$output" '__SMOKE_FLAKE__' 'workspace contents' >/dev/null
  require_line "$output" '__SMOKE_CONFIG_OK__' 'tool state usability' >/dev/null
  if [ "$expected_config_dir" = "/run/firebreak-state-root/@STATE_SUBDIR@" ]; then
    require_line "$output" '__SMOKE_HOST_CONFIG__' 'host config marker' >/dev/null
  fi
  require_line "$output" '__SMOKE_AGENT__' '@AGENT_DISPLAY_NAME@ CLI' >/dev/null

  printf '%s\n' "ok: $scenario_label"
}

run_agent_exec_scenario() {
  mode=$1
  scenario_label=$2
  agent_cli_arg=$3

  printf '%s\n' "running: $scenario_label"
  set +e
  output=$(
    run_with_clean_firebreak_env \
      FIREBREAK_STATE_MODE="$mode" \
      FIREBREAK_INSTANCE_EPHEMERAL=1 \
      timeout --foreground "$timeout_seconds" \
      bash "$run_flake" run .#@AGENT_PACKAGE@ -- "$agent_cli_arg" 2>&1
  )
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    echo "one-shot agent command failed for: $scenario_label" >&2
    exit 1
  fi

  case "$output" in
    *[0-9].[0-9]* | *[0-9].[0-9].[0-9]*)
      ;;
    *)
      printf '%s\n' "$output" >&2
      echo "one-shot agent command did not print a recognizable version string for: $scenario_label" >&2
      exit 1
      ;;
  esac

  printf '%s\n' "ok: $scenario_label"
}

run_agent_exec_scenario workspace "default agent entry runs @AGENT_BIN@ --version as a one-shot command" "--version"
run_scenario @AGENT_PACKAGE@ workspace "$expected_workspace_config_dir" "shell override uses workspace config"
if [ -e "$repo_root/@STATE_DIR_NAME@" ]; then
  echo "workspace mode should not create a Firebreak-managed project config overlay: $repo_root/@STATE_DIR_NAME@" >&2
  exit 1
fi
run_scenario @AGENT_PACKAGE@ vm "/var/lib/dev/@STATE_DIR_NAME@" "shell override uses vm config"
run_scenario @AGENT_PACKAGE@ host "/run/firebreak-state-root/@STATE_SUBDIR@" "shell override uses host config" "$host_config_root"

printf '%s\n' "Firebreak smoke test passed"
