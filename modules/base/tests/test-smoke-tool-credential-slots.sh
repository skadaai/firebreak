#!/usr/bin/env bash
set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-@AGENT_BIN@-credential-slots.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

credential_root=$smoke_tmp_dir/credentials
workspace_dir=$smoke_tmp_dir/workspace
mkdir -p \
  "$credential_root/default/@STATE_SUBDIR@" \
  "$credential_root/alternate/@STATE_SUBDIR@" \
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

cat >"$credential_root/default/@STATE_SUBDIR@/@AUTH_FILE@" <<'EOF'
default-auth
EOF
cat >"$credential_root/default/@STATE_SUBDIR@/@API_KEY_FILE@" <<'EOF'
default-api-key
EOF
cat >"$credential_root/alternate/@STATE_SUBDIR@/@AUTH_FILE@" <<'EOF'
alternate-auth
EOF
cat >"$credential_root/alternate/@STATE_SUBDIR@/@API_KEY_FILE@" <<'EOF'
alternate-api-key
EOF

(
  cd "$workspace_dir"
  git init -q
)

project_key=$(state_sha256 "$workspace_dir")
project_key=$(printf '%.16s' "$project_key")
expected_workspace_root="/run/firebreak-state-root/workspaces/$project_key/@STATE_SUBDIR@"

make_fake_real_bin_command=$(cat <<'EOF'
mkdir -p "$LOCAL_BIN"
cleanup_fake_real_bin() {
  rm -f "$LOCAL_BIN/@AGENT_BIN@"
}
trap cleanup_fake_real_bin EXIT
cat >"$LOCAL_BIN/@AGENT_BIN@" <<'EOS'
#!/usr/bin/env bash
set -eu

login_args=(
@LOGIN_COMMAND_ARGS@
)

is_login_command() {
  [ "${#login_args[@]}" -gt 0 ] || return 1
  [ "$#" -ge "${#login_args[@]}" ] || return 1

  index=0
  while [ "$index" -lt "${#login_args[@]}" ]; do
    eval "current_arg=\${$((index + 1))}"
    if [ "$current_arg" != "${login_args[$index]}" ]; then
      return 1
    fi
    index=$((index + 1))
  done

  return 0
}

config_root="${@CONFIG_ROOT_ENV@:-${FIREBREAK_TOOL_STATE_DIR:-}}"

if is_login_command "$@"; then
  eval "token=\${$(( ${#login_args[@]} + 1 )):-smoke-login-token}"
  mkdir -p "$config_root"
  printf '%s\n' "$token" >"$config_root/@AUTH_FILE@"
  printf 'LOGIN_ROOT=%s\n' "$config_root"
  exit 0
fi

printf 'CONFIG_ROOT=%s\n' "$config_root"
if [ -r "$config_root/@AUTH_FILE@" ]; then
  printf 'AUTH_FILE=%s\n' "$(cat "$config_root/@AUTH_FILE@")"
fi
printf 'API_KEY=%s\n' "${@API_KEY_ENV@:-}"
EOS
chmod 0555 "$LOCAL_BIN/@AGENT_BIN@"
EOF
)

run_shell_scenario() {
  command_body=$1
  slot_name=$2
  extra_env_key=${3-}
  extra_env_value=${4-}

  if [ -n "$extra_env_key" ]; then
    output=$(
      cd "$workspace_dir"
      run_with_clean_firebreak_env \
        FIREBREAK_INSTANCE_EPHEMERAL=1 \
        FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$credential_root" \
        FIREBREAK_STATE_MODE=workspace \
        FIREBREAK_CREDENTIAL_SLOT="$slot_name" \
        "$extra_env_key=$extra_env_value" \
        AGENT_VM_COMMAND="$command_body" \
        FIREBREAK_LAUNCH_MODE=shell \
        nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
          "path:$repo_root#@AGENT_PACKAGE@" 2>&1
    )
  else
    output=$(
      cd "$workspace_dir"
      run_with_clean_firebreak_env \
        FIREBREAK_INSTANCE_EPHEMERAL=1 \
        FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$credential_root" \
        FIREBREAK_STATE_MODE=workspace \
        FIREBREAK_CREDENTIAL_SLOT="$slot_name" \
        AGENT_VM_COMMAND="$command_body" \
        FIREBREAK_LAUNCH_MODE=shell \
        nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
          "path:$repo_root#@AGENT_PACKAGE@" 2>&1
    )
  fi

  printf '%s\n' "$output"
}

probe_output=$(run_shell_scenario "$make_fake_real_bin_command
@AGENT_BIN@ probe" default)
require_pattern "$probe_output" "CONFIG_ROOT=$expected_workspace_root" "workspace state root"
require_pattern "$probe_output" "AUTH_FILE=default-auth" "default slot auth file"
require_pattern "$probe_output" "API_KEY=default-api-key" "default slot API key"

override_output=$(run_shell_scenario "$make_fake_real_bin_command
@AGENT_BIN@ probe" default "@CREDENTIAL_SLOT_SPECIFIC_VAR@" alternate)
require_pattern "$override_output" "CONFIG_ROOT=$expected_workspace_root" "override workspace state root"
require_pattern "$override_output" "AUTH_FILE=alternate-auth" "override slot auth file"
require_pattern "$override_output" "API_KEY=alternate-api-key" "override slot API key"

login_output=$(run_shell_scenario "$make_fake_real_bin_command
@AGENT_BIN@ @LOGIN_COMMAND@ direct-login-auth" login-slot)
require_pattern "$login_output" "LOGIN_ROOT=/run/credential-slots-host-root/login-slot/@STATE_SUBDIR@" "slot-root login materialization"
if [ "$(cat "$credential_root/login-slot/@STATE_SUBDIR@/@AUTH_FILE@")" != "direct-login-auth" ]; then
  echo "@AGENT_DISPLAY_NAME@ credential smoke did not write the login result into the selected slot" >&2
  exit 1
fi

printf '%s\n' "Firebreak @AGENT_DISPLAY_NAME@ credential-slot smoke test passed"
