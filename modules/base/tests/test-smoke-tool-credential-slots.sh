#!/usr/bin/env bash
set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the Firebreak repository" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$repo_root/modules/base/host/firebreak-project-config.sh"

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-@TOOL_BIN@-credential-slots.XXXXXX")
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
  while IFS= read -r env_key; do
    [ -n "$env_key" ] || continue
    unset "$env_key"
  done <<EOF
$(firebreak_list_scrubbable_env_keys)
EOF

  unset FIREBREAK_INSTANCE_DIR FIREBREAK_STATE_DIR

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

case '@AUTH_FILE_FORMAT@' in
  json)
    cat >"$credential_root/default/@STATE_SUBDIR@/@AUTH_FILE@" <<'EOF'
"default-auth"
EOF
    ;;
  *)
    cat >"$credential_root/default/@STATE_SUBDIR@/@AUTH_FILE@" <<'EOF'
default-auth
EOF
    ;;
esac
cat >"$credential_root/default/@STATE_SUBDIR@/@API_KEY_FILE@" <<'EOF'
default-api-key
EOF
case '@AUTH_FILE_FORMAT@' in
  json)
    cat >"$credential_root/alternate/@STATE_SUBDIR@/@AUTH_FILE@" <<'EOF'
"alternate-auth"
EOF
    ;;
  *)
    cat >"$credential_root/alternate/@STATE_SUBDIR@/@AUTH_FILE@" <<'EOF'
alternate-auth
EOF
    ;;
esac
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
fake_local_bin=$(mktemp -d "${TMPDIR:-/tmp}/firebreak-fake-bin.XXXXXX")
LOCAL_BIN="$fake_local_bin"
export LOCAL_BIN
mkdir -p "$LOCAL_BIN"
cleanup_fake_real_bin() {
  rm -rf "$fake_local_bin"
}
trap cleanup_fake_real_bin EXIT
cat >"$LOCAL_BIN/@TOOL_BIN@" <<'EOS'
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
    position=$((index + 1))
    current_arg=${!position}
    if [ "$current_arg" != "${login_args[$index]}" ]; then
      return 1
    fi
    index=$((index + 1))
  done

  return 0
}

config_root="${@CONFIG_ROOT_ENV@:-${FIREBREAK_TOOL_STATE_DIR:-}}"

if is_login_command "$@"; then
  token_position=$(( ${#login_args[@]} + 1 ))
  token=${!token_position:-smoke-login-token}
  mkdir -p "$config_root"
  case '@AUTH_FILE_FORMAT@' in
    json)
      @PYTHON3@ - "$config_root/@AUTH_FILE@" "$token" <<'PY'
import json
import sys

path = sys.argv[1]
value = sys.argv[2]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle)
PY
      ;;
    *)
      printf '%s\n' "$token" >"$config_root/@AUTH_FILE@"
      ;;
  esac
  printf 'LOGIN_ROOT=%s\n' "$config_root"
  exit 0
fi

printf 'CONFIG_ROOT=%s\n' "$config_root"
if [ -r "$config_root/@AUTH_FILE@" ]; then
  case '@AUTH_FILE_FORMAT@' in
    json)
      auth_value=$(@PYTHON3@ - "$config_root/@AUTH_FILE@" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    value = json.load(handle)
if isinstance(value, str):
    print(value)
else:
    print(json.dumps(value, sort_keys=True))
PY
)
      ;;
    *)
      auth_value=$(cat "$config_root/@AUTH_FILE@")
      ;;
  esac
  printf 'AUTH_FILE=%s\n' "$auth_value"
fi
printf 'API_KEY=%s\n' "${@API_KEY_ENV@:-}"
EOS
chmod 0555 "$LOCAL_BIN/@TOOL_BIN@"
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
        WORKLOAD_VM_COMMAND="$command_body" \
        FIREBREAK_LAUNCH_MODE=shell \
        nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
          "path:$repo_root#@WORKLOAD_PACKAGE@" 2>&1
    )
  else
    output=$(
      cd "$workspace_dir"
      run_with_clean_firebreak_env \
        FIREBREAK_INSTANCE_EPHEMERAL=1 \
        FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$credential_root" \
        FIREBREAK_STATE_MODE=workspace \
        FIREBREAK_CREDENTIAL_SLOT="$slot_name" \
        WORKLOAD_VM_COMMAND="$command_body" \
        FIREBREAK_LAUNCH_MODE=shell \
        nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
          "path:$repo_root#@WORKLOAD_PACKAGE@" 2>&1
    )
  fi

  printf '%s\n' "$output"
}

probe_output=$(run_shell_scenario "$make_fake_real_bin_command
@TOOL_BIN@ probe" default)
require_pattern "$probe_output" "CONFIG_ROOT=$expected_workspace_root" "workspace state root"
require_pattern "$probe_output" "AUTH_FILE=default-auth" "default slot auth file"
require_pattern "$probe_output" "API_KEY=default-api-key" "default slot API key"

override_output=$(run_shell_scenario "$make_fake_real_bin_command
@TOOL_BIN@ probe" default "@CREDENTIAL_SLOT_SPECIFIC_VAR@" alternate)
require_pattern "$override_output" "CONFIG_ROOT=$expected_workspace_root" "override workspace state root"
require_pattern "$override_output" "AUTH_FILE=alternate-auth" "override slot auth file"
require_pattern "$override_output" "API_KEY=alternate-api-key" "override slot API key"

login_output=$(run_shell_scenario "$make_fake_real_bin_command
@TOOL_BIN@ @LOGIN_COMMAND@ direct-login-auth" login-slot)
require_pattern "$login_output" "LOGIN_ROOT=/run/credential-slots-host-root/login-slot/@STATE_SUBDIR@" "slot-root login materialization"
if [ "$(@PYTHON3@ - "$credential_root/login-slot/@STATE_SUBDIR@/@AUTH_FILE@" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle))
PY
)" != "direct-login-auth" ]; then
  echo "@TOOL_DISPLAY_NAME@ credential smoke did not write the login result into the selected slot" >&2
  exit 1
fi

printf '%s\n' "Firebreak @TOOL_DISPLAY_NAME@ credential-slot smoke test passed"
