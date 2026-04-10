# shellcheck shell=bash

load_firebreak_shared_credential_defaults() {
  env_file=${FIREBREAK_SHARED_CREDENTIAL_SLOTS_ENV_FILE:-/run/microvm-host-meta/firebreak-shared-state.env}
  if [ -r "$env_file" ]; then
    # shellcheck disable=SC1090
    . "$env_file"
  fi
}

resolve_selected_credential_slot() {
  specific_var=$1
  printf '%s\n' "${!specific_var:-${FIREBREAK_CREDENTIAL_SLOT:-}}"
}

resolve_selected_credential_slot_root() {
  selected_slot=$1
  slot_subdir=$2

  [ -n "$selected_slot" ] || return 0

  case "$selected_slot" in
    *[\\/]*|*..*|*[!A-Za-z0-9._-]*)
      printf '%s\n' "invalid Firebreak credential slot name: $selected_slot" >&2
      exit 1
      ;;
  esac

  mounted_flag=${FIREBREAK_SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG:-/run/firebreak-shared-credential-slots-mounted}
  if ! [ -e "$mounted_flag" ]; then
    printf '%s\n' "Firebreak credential slots are not mounted; select a different state mode or inspect prepare-worker-session logs for the credential-slot mount failure." >&2
    exit 1
  fi

  slot_root=${FIREBREAK_SHARED_CREDENTIAL_SLOTS_HOST_MOUNT:-/run/credential-slots-host-root}/$selected_slot/$slot_subdir
  mkdir -p "$slot_root"
  printf '%s\n' "$slot_root"
}
