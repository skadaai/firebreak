set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

host_uid=$(id -u)
host_gid=$(id -g)
timeout_seconds=${FIREBREAK_SMOKE_TIMEOUT:-${CODEX_VM_SMOKE_TIMEOUT:-900}}
firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
host_config_dir=$(mktemp -d "$firebreak_tmp_root/agent-smoke-config.XXXXXX")
workspace_config_host_path=""
expected_workspace_config_dir=""

cleanup() {
  rm -rf "$host_config_dir"
}
trap cleanup EXIT INT TERM

printf '%s\n' "host-smoke-marker" > "$host_config_dir/marker.txt"

workspace_config_host_path=$repo_root/@AGENT_CONFIG_DIR_NAME@
expected_workspace_config_dir=$repo_root/@AGENT_CONFIG_DIR_NAME@
if [ -L "$workspace_config_host_path" ]; then
  workspace_config_target=$(realpath -m "$workspace_config_host_path")
  case "$workspace_config_target" in
    "$repo_root"|"$repo_root"/*)
      ;;
    *)
      expected_workspace_config_dir="/run/agent-config-host"
      ;;
  esac
fi

smoke_probe_command=$(cat <<'EOF'
printf '__SMOKE_PWD__%s\n' "$PWD"
printf '__SMOKE_IDS__%s:%s\n' "$(id -u)" "$(id -g)"
printf '__SMOKE_OWNER__%s\n' "$(stat -c %u:%g .)"
printf '__SMOKE_CONFIG_DIR__%s\n' "${AGENT_CONFIG_DIR:-}"
test -f flake.nix
printf '__SMOKE_FLAKE__ok\n'
test -d "$AGENT_CONFIG_DIR"
test -w "$AGENT_CONFIG_DIR"
printf '__SMOKE_CONFIG_OK__ok\n'
if [ "$AGENT_CONFIG_DIR" = "/run/agent-config-host" ]; then
  test -f "$AGENT_CONFIG_DIR/marker.txt"
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

run_scenario() {
  package_name=$1
  mode=$2
  expected_config_dir=$3
  scenario_label=$4
  host_config_path=${5-}

  printf '%s\n' "running: $scenario_label"

  set +e
  output=$(
    AGENT_CONFIG=$mode \
      FIREBREAK_VM_MODE=shell \
      FIREBREAK_INSTANCE_EPHEMERAL=1 \
      AGENT_CONFIG_HOST_PATH="${host_config_path:-}" \
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

  agent_config_dir=$(require_line "$output" '__SMOKE_CONFIG_DIR__' 'agent config directory')
  if [ "$agent_config_dir" != "$expected_config_dir" ]; then
    printf '%s\n' "$output" >&2
    echo "unexpected agent config directory: $agent_config_dir" >&2
    exit 1
  fi

  require_line "$output" '__SMOKE_FLAKE__' 'workspace contents' >/dev/null
  require_line "$output" '__SMOKE_CONFIG_OK__' 'agent config usability' >/dev/null
  if [ "$expected_config_dir" = "/run/agent-config-host" ]; then
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
    AGENT_CONFIG=$mode \
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
run_scenario @AGENT_PACKAGE@ vm "/var/lib/dev/@AGENT_CONFIG_DIR_NAME@" "shell override uses vm config"
run_scenario @AGENT_PACKAGE@ host "/run/agent-config-host" "shell override uses host config" "$host_config_dir"

printf '%s\n' "Firebreak smoke test passed"
