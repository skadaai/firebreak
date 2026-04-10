#!/usr/bin/env bash
set -eu

@FIREBREAK_SHARED_STATE_ROOT_LIB@
@FIREBREAK_SHARED_CREDENTIAL_SLOT_LIB@

export FIREBREAK_STATE_MODE_SPECIFIC_VAR='@SPECIFIC_STATE_MODE_VAR@'
export FIREBREAK_STATE_SUBDIR='@STATE_SUBDIR@'
export FIREBREAK_STATE_DISPLAY_NAME='@WRAPPER_DISPLAY_NAME@'

credential_file_bindings=$(cat <<'EOF'
@CREDENTIAL_FILE_BINDINGS@
EOF
)

credential_env_bindings=$(cat <<'EOF'
@CREDENTIAL_ENV_BINDINGS@
EOF
)

credential_helper_bindings=$(cat <<'EOF'
@CREDENTIAL_HELPER_BINDINGS@
EOF
)

credential_login_args=(
@CREDENTIAL_LOGIN_ARGS@
)

resolve_real_bin() {
  real_bin_name='@REAL_BIN_NAME@'

  if [ -n "${BUN_INSTALL:-}" ] && [ -x "$BUN_INSTALL/bin/$real_bin_name" ]; then
    printf '%s\n' "$BUN_INSTALL/bin/$real_bin_name"
    return 0
  fi

  if [ -n "${LOCAL_BIN:-}" ] && [ -x "$LOCAL_BIN/$real_bin_name" ]; then
    printf '%s\n' "$LOCAL_BIN/$real_bin_name"
    return 0
  fi

  if [ -x '@REAL_BIN_TOOLS_FALLBACK@' ]; then
    printf '%s\n' '@REAL_BIN_TOOLS_FALLBACK@'
    return 0
  fi

  if [ -x '@REAL_BIN_HOME_FALLBACK@' ]; then
    printf '%s\n' '@REAL_BIN_HOME_FALLBACK@'
    return 0
  fi

  if [ -x '@REAL_BIN_PATH@' ]; then
    printf '%s\n' '@REAL_BIN_PATH@'
    return 0
  fi

  printf '%s\n' "Firebreak could not resolve the installed @WRAPPER_DISPLAY_NAME@ binary (@REAL_BIN_NAME@)." >&2
  printf '%s\n' "Expected one of: \$LOCAL_BIN/@REAL_BIN_NAME@, \$BUN_INSTALL/bin/@REAL_BIN_NAME@, @REAL_BIN_TOOLS_FALLBACK@, @REAL_BIN_HOME_FALLBACK@, or @REAL_BIN_PATH@" >&2
  exit 1
}

ensure_parent_dir() {
  target_path=$1
  parent_dir=$(dirname "$target_path")
  mkdir -p "$parent_dir"
}

render_helper_script() {
  helper_path=$1
  slot_path=$2
  helper_display_name=$3

  cat >"$helper_path" <<EOF
#!/usr/bin/env bash
set -eu
slot_path='$(printf '%s' "$slot_path" | sed "s/'/'\\\\''/g")'
if ! [ -r "\$slot_path" ]; then
  printf '%s\n' "missing Firebreak credential material for $helper_display_name: \$slot_path" >&2
  exit 1
fi
cat "\$slot_path"
EOF
  chmod 0700 "$helper_path"
}

is_login_command() {
  [ "${#credential_login_args[@]}" -gt 0 ] || return 1
  [ "$#" -ge "${#credential_login_args[@]}" ] || return 1

  index=0
  while [ "$index" -lt "${#credential_login_args[@]}" ]; do
    position=$((index + 1))
    current_arg=${!position}
    if [ "$current_arg" != "${credential_login_args[$index]}" ]; then
      return 1
    fi
    index=$((index + 1))
  done

  return 0
}

validate_json_file() {
  target_path=$1
  description=$2

  if ! [ -e "$target_path" ]; then
    return 0
  fi

  if ! [ -s "$target_path" ]; then
    printf '%s\n' "Firebreak found an empty JSON credential file for @WRAPPER_DISPLAY_NAME@: $target_path" >&2
    printf '%s\n' "Remove the file, restore valid credentials, or rerun the native login flow to recreate it." >&2
    exit 1
  fi

  if ! @PYTHON3@ - "$target_path" "$description" <<'EOF'
import json
import sys

path = sys.argv[1]
description = sys.argv[2]

try:
    with open(path, "r", encoding="utf-8") as handle:
        json.load(handle)
except Exception as exc:  # noqa: BLE001
    print(
        f"Firebreak found invalid JSON credential material for {description}: {path}: {exc}",
        file=sys.stderr,
    )
    sys.exit(1)
EOF
  then
    exit 1
  fi
}

prepare_json_file_for_login() {
  target_path=$1

  if [ -e "$target_path" ] && ! [ -s "$target_path" ]; then
    rm -f "$target_path"
    printf '%s\n' "firebreak: removed empty JSON credential file before native login: $target_path" >&2
  fi
}

validate_json_bindings() {
  [ -n "$credential_file_bindings" ] || return 0

  login_mode=0
  if is_login_command "$@"; then
    login_mode=1
  fi

  tab=$(printf '\t')
  while IFS="$tab" read -r slot_rel_path runtime_rel_path _binding_required binding_format || [ -n "$slot_rel_path" ]; do
    [ -n "$slot_rel_path" ] || continue
    [ "$binding_format" = "json" ] || continue

    runtime_path=$tool_state_dir/$runtime_rel_path
    if [ "$login_mode" = "1" ]; then
      prepare_json_file_for_login "$runtime_path"
    fi

    if [ -e "$runtime_path" ]; then
      validate_json_file "$runtime_path" "@WRAPPER_DISPLAY_NAME@ runtime state"
      continue
    fi

    if [ -n "$selected_slot_root" ]; then
      slot_path=$selected_slot_root/$slot_rel_path
      if [ -e "$slot_path" ]; then
        if [ "$login_mode" = "1" ] && [ "$runtime_path" = "$slot_path" ]; then
          prepare_json_file_for_login "$slot_path"
          if [ -e "$slot_path" ]; then
            validate_json_file "$slot_path" "@WRAPPER_DISPLAY_NAME@ credential slot"
          fi
        else
          validate_json_file "$slot_path" "@WRAPPER_DISPLAY_NAME@ credential slot"
        fi
      fi
    fi
  done <<EOF
$credential_file_bindings
EOF
}

apply_file_bindings() {
  [ -n "$selected_slot_root" ] || return 0
  [ -n "$credential_file_bindings" ] || return 0

  tab=$(printf '\t')
  while IFS="$tab" read -r slot_rel_path runtime_rel_path binding_required _binding_format || [ -n "$slot_rel_path" ]; do
    [ -n "$slot_rel_path" ] || continue
    slot_path=$selected_slot_root/$slot_rel_path
    runtime_path=$tool_state_dir/$runtime_rel_path

    if [ "$runtime_path" = "$slot_path" ]; then
      continue
    fi

    if [ -r "$slot_path" ]; then
      ensure_parent_dir "$runtime_path"
      cp "$slot_path" "$runtime_path"
    elif [ "$binding_required" = "1" ]; then
      printf '%s\n' "missing required Firebreak credential file for @WRAPPER_DISPLAY_NAME@: $slot_path" >&2
      exit 1
    fi
  done <<EOF
$credential_file_bindings
EOF
}

sync_file_bindings_back() {
  [ -n "$selected_slot_root" ] || return 0
  [ -n "$credential_file_bindings" ] || return 0

  tab=$(printf '\t')
  while IFS="$tab" read -r slot_rel_path runtime_rel_path _binding_required _binding_format || [ -n "$slot_rel_path" ]; do
    [ -n "$slot_rel_path" ] || continue
    slot_path=$selected_slot_root/$slot_rel_path
    runtime_path=$tool_state_dir/$runtime_rel_path

    if [ "$runtime_path" = "$slot_path" ]; then
      continue
    fi

    if [ -r "$runtime_path" ]; then
      ensure_parent_dir "$slot_path"
      cp "$runtime_path" "$slot_path"
    fi
  done <<EOF
$credential_file_bindings
EOF
}

apply_env_bindings() {
  [ -n "$selected_slot_root" ] || return 0
  [ -n "$credential_env_bindings" ] || return 0

  tab=$(printf '\t')
  while IFS="$tab" read -r slot_rel_path env_var_name binding_required || [ -n "$slot_rel_path" ]; do
    [ -n "$slot_rel_path" ] || continue
    slot_path=$selected_slot_root/$slot_rel_path

    if [ -r "$slot_path" ]; then
      env_value=$(cat "$slot_path")
      printf -v "$env_var_name" '%s' "$env_value"
      export "${env_var_name?}"
    elif [ "$binding_required" = "1" ]; then
      printf '%s\n' "missing required Firebreak credential value for @WRAPPER_DISPLAY_NAME@: $slot_path" >&2
      exit 1
    fi
  done <<EOF
$credential_env_bindings
EOF
}

apply_helper_bindings() {
  [ -n "$selected_slot_root" ] || return 0
  [ -n "$credential_helper_bindings" ] || return 0

  helper_root=$(mktemp -d "${TMPDIR:-/tmp}/firebreak-credential-helpers.XXXXXX")

  tab=$(printf '\t')
  while IFS="$tab" read -r slot_rel_path helper_name env_var_name binding_required || [ -n "$slot_rel_path" ]; do
    [ -n "$slot_rel_path" ] || continue
    slot_path=$selected_slot_root/$slot_rel_path

    if ! [ -r "$slot_path" ]; then
      if [ "$binding_required" = "1" ]; then
        printf '%s\n' "missing required Firebreak helper credential material for @WRAPPER_DISPLAY_NAME@: $slot_path" >&2
        exit 1
      fi
      continue
    fi

    helper_path=$helper_root/$helper_name
    render_helper_script "$helper_path" "$slot_path" "@WRAPPER_DISPLAY_NAME@"
    printf -v "$env_var_name" '%s' "$helper_path"
    export "${env_var_name?}"
  done <<EOF
$credential_helper_bindings
EOF
}

cleanup_helper_root() {
  if [ -n "${helper_root:-}" ] && [ -d "$helper_root" ]; then
    rm -rf "$helper_root"
  fi
}

trap cleanup_helper_root EXIT

load_firebreak_shared_credential_defaults
state_root_dir=$(@RESOLVE_STATE_ROOT_BIN@)
selected_slot=$(resolve_selected_credential_slot '@CREDENTIAL_SLOT_SPECIFIC_VAR@')
selected_slot_root=""
if [ -n "$selected_slot" ]; then
  selected_slot_root=$(resolve_selected_credential_slot_root "$selected_slot" '@CREDENTIAL_SLOT_SUBDIR@')
fi

tool_state_dir=$state_root_dir
if is_login_command "$@" && [ -n "$selected_slot_root" ] && [ '@CREDENTIAL_LOGIN_MATERIALIZATION@' = 'slot-root' ]; then
  tool_state_dir=$selected_slot_root
fi

export FIREBREAK_TOOL_STATE_DIR="$tool_state_dir"
validate_json_bindings "$@"
apply_file_bindings
apply_env_bindings
apply_helper_bindings
@CONFIG_ENV_EXPORTS@

real_bin=$(resolve_real_bin)
if "$real_bin" "$@"; then
  command_status=0
  sync_file_bindings_back
else
  command_status=$?
fi
exit "$command_status"
