# shellcheck disable=SC2034
FIREBREAK_PROJECT_CONFIG_KEYS="
FIREBREAK_ENVIRONMENT_MODE
FIREBREAK_ENVIRONMENT_INSTALLABLE
"

firebreak_project_config_is_registered_key() {
  lookup_key=$1
  case "
$FIREBREAK_PROJECT_CONFIG_KEYS
" in
    *"
$lookup_key
"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# shellcheck disable=SC2329

trim_whitespace() {
  value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

firebreak_reset_project_config_state() {
  FIREBREAK_RESOLVED_PROJECT_ROOT=""
  # shellcheck disable=SC2034
  FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE=""
  FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE=""
  # shellcheck disable=SC2034
  FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE="none"
  FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS=""
  while IFS= read -r project_key; do
    [ -n "$project_key" ] || continue
    eval "$project_key=\${$project_key:-}"
  done <<EOF
$FIREBREAK_PROJECT_CONFIG_KEYS
EOF
}

firebreak_project_config_key_allowed() {
  if firebreak_project_config_is_registered_key "$1"; then
    return 0
  fi
  case "$1" in
    FIREBREAK_STATE_MODE|FIREBREAK_STATE_ROOT|FIREBREAK_STATE_DIR|FIREBREAK_INSTANCE_DIR|FIREBREAK_INSTANCE_EPHEMERAL|FIREBREAK_LAUNCH_MODE|FIREBREAK_WORKER_MODE|FIREBREAK_WORKER_MODES|FIREBREAK_CREDENTIAL_SLOT|FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH)
      return 0
      ;;
    *_STATE_MODE)
      return 0
      ;;
    *_CREDENTIAL_SLOT)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# shellcheck disable=SC2329
firebreak_should_scrub_env_key() {
  if firebreak_project_config_is_registered_key "$1"; then
    return 0
  fi
  case "$1" in
    FIREBREAK_STATE_MODE|FIREBREAK_STATE_ROOT|FIREBREAK_STATE_DIR|FIREBREAK_INSTANCE_DIR|FIREBREAK_INSTANCE_EPHEMERAL|FIREBREAK_LAUNCH_MODE|FIREBREAK_WORKER_MODE|FIREBREAK_WORKER_MODES|FIREBREAK_CREDENTIAL_SLOT|FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH|*_CREDENTIAL_SLOT|*_STATE_MODE)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# shellcheck disable=SC2329
firebreak_list_scrubbable_env_keys() {
  while IFS='=' read -r env_key _; do
    if firebreak_should_scrub_env_key "$env_key"; then
      printf '%s\n' "$env_key"
    fi
  done <<EOF
$(env)
EOF
}

firebreak_record_ignored_key() {
  ignored_key=$1
  case "
$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS
" in
    *"
$ignored_key
"*)
      ;;
    *)
      FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS="${FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS}${FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS:+
}$ignored_key"
      ;;
  esac
}

firebreak_record_original_env_key() {
  original_key=$1
  case "
$FIREBREAK_ORIGINAL_ENV_KEYS
" in
    *"
$original_key
"*)
      ;;
    *)
      FIREBREAK_ORIGINAL_ENV_KEYS="${FIREBREAK_ORIGINAL_ENV_KEYS}${FIREBREAK_ORIGINAL_ENV_KEYS:+
}$original_key"
      ;;
  esac
}

firebreak_snapshot_original_env() {
  FIREBREAK_ORIGINAL_ENV_KEYS=""
  while IFS= read -r original_entry; do
    original_key=${original_entry%%=*}
    [ -n "$original_key" ] || continue
    firebreak_record_original_env_key "$original_key"
  done <<EOF
$(env)
EOF
}

firebreak_original_env_has_key() {
  lookup_key=$1
  case "
$FIREBREAK_ORIGINAL_ENV_KEYS
" in
    *"
$lookup_key
"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

firebreak_resolve_project_root() {
  if [ -n "${FIREBREAK_RESOLVED_PROJECT_ROOT:-}" ]; then
    return 0
  fi

  git_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$git_root" ]; then
    FIREBREAK_RESOLVED_PROJECT_ROOT=$git_root
    # shellcheck disable=SC2034
    FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE="git"
  else
    FIREBREAK_RESOLVED_PROJECT_ROOT=$PWD
    # shellcheck disable=SC2034
    FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE="cwd"
  fi
}

firebreak_resolve_project_config_file() {
  firebreak_resolve_project_root

  if [ -n "${FIREBREAK_PROJECT_CONFIG_FILE:-}" ]; then
    FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE=$FIREBREAK_PROJECT_CONFIG_FILE
    # shellcheck disable=SC2034
    FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE="env"
    return 0
  fi

  candidate_path=$FIREBREAK_RESOLVED_PROJECT_ROOT/.firebreak.env
  if [ -f "$candidate_path" ]; then
    FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE=$candidate_path
    # shellcheck disable=SC2034
    FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE="project-default"
    return 0
  fi

  FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE=$candidate_path
  # shellcheck disable=SC2034
  FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE="none"
}

firebreak_load_project_config() {
  firebreak_reset_project_config_state
  firebreak_resolve_project_config_file
  firebreak_snapshot_original_env

  if ! [ -f "$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE" ]; then
    return 0
  fi

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line=$(trim_whitespace "$raw_line")
    [ -n "$line" ] || continue
    case "$line" in
      \#*)
        continue
        ;;
      *=*)
        ;;
      *)
        continue
        ;;
    esac

    key=$(trim_whitespace "${line%%=*}")
    value=$(trim_whitespace "${line#*=}")

    case "$key" in
      ""|*[!A-Za-z0-9_]*)
        continue
        ;;
    esac

    if ! firebreak_project_config_key_allowed "$key"; then
      firebreak_record_ignored_key "$key"
      continue
    fi

    if [ "${value#\"}" != "$value" ] && [ "${value%\"}" != "$value" ] && [ "${#value}" -ge 2 ]; then
      value=${value#\"}
      value=${value%\"}
    elif [ "${value#\'}" != "$value" ] && [ "${value%\'}" != "$value" ] && [ "${#value}" -ge 2 ]; then
      value=${value#\'}
      value=${value%\'}
    fi

    if firebreak_original_env_has_key "$key"; then
      continue
    fi

    printf -v "$key" '%s' "$value"
    # shellcheck disable=SC2163
    export "$key"
  done <"$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE"
}
