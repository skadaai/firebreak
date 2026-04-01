firebreak_doctor_usage() {
  cat <<'EOF' >&2
usage:
  firebreak doctor [--verbose] [--json]
EOF
  exit 1
}

firebreak_doctor_resolve_host_dir() {
  path=$1
  if [ "$path" = "~" ]; then
    printf '%s\n' "$HOME"
  elif [ "${path#\~/}" != "$path" ]; then
    printf '%s\n' "$HOME/${path#\~/}"
  else
    printf '%s\n' "$path"
  fi
}

firebreak_doctor_json_escape() {
  FIREBREAK_DOCTOR_JSON_VALUE=$1 python3 - <<'PY'
import json
import os

print(json.dumps(os.environ["FIREBREAK_DOCTOR_JSON_VALUE"])[1:-1], end="")
PY
}

firebreak_doctor_json_array() {
  list=$1
  if [ -z "$list" ]; then
    return 0
  fi

  first=1
  printf '%s\n' "$list" | while IFS= read -r item; do
    [ -n "$item" ] || continue
    if [ "$first" = "1" ]; then
      first=0
    else
      printf ', '
    fi
    printf '"%s"' "$(firebreak_doctor_json_escape "$item")"
  done
}

firebreak_doctor_report_line() {
  key=$1
  value=$2
  printf '%-24s %s\n' "$key" "$value"
}

firebreak_doctor_host_platform() {
  host_os=$(uname -s 2>/dev/null || printf '%s' unknown)
  host_arch=$(uname -m 2>/dev/null || printf '%s' unknown)
  host_os=$(printf '%s' "$host_os" | tr '[:upper:]' '[:lower:]')
  printf '%s-%s\n' "$host_arch" "$host_os"
}

firebreak_doctor_local_runtime() {
  case "$(uname -s 2>/dev/null || printf '%s' unknown):$(uname -m 2>/dev/null || printf '%s' unknown)" in
    Linux:*)
      printf '%s\n' "qemu"
      ;;
    Darwin:arm64|Darwin:aarch64)
      printf '%s\n' "vfkit"
      ;;
    Darwin:*)
      printf '%s\n' "unsupported-intel-mac"
      ;;
    *)
      printf '%s\n' "unsupported-host"
      ;;
  esac
}

firebreak_doctor_detect_kvm() {
  if ! [ -e /dev/kvm ]; then
    printf '%s\n' "missing"
  elif ! [ -r /dev/kvm ]; then
    printf '%s\n' "not-readable"
  elif ! [ -w /dev/kvm ]; then
    printf '%s\n' "not-writable"
  else
    printf '%s\n' "ok"
  fi
}

firebreak_doctor_git_common_dir() {
  git rev-parse --git-common-dir 2>/dev/null || true
}

firebreak_doctor_primary_checkout_state() {
  git_common_dir=$1
  case "$git_common_dir" in
    .git)
      printf '%s\n' "yes"
      ;;
    "")
      printf '%s\n' "unknown"
      ;;
    *)
      printf '%s\n' "no"
      ;;
  esac
}

firebreak_doctor_workspace_config_path() {
  config_dir_name=$1
  candidate_path=$PWD/$config_dir_name

  if [ -L "$candidate_path" ]; then
    resolved_target=$(realpath -m "$candidate_path")
    case "$resolved_target" in
      "$PWD"|"$PWD"/*)
        printf '%s\n' "$candidate_path"
        ;;
      *)
        printf '%s\n' "$resolved_target"
        ;;
    esac
  else
    printf '%s\n' "$candidate_path"
  fi
}

firebreak_doctor_resolve_agent_state() {
  agent_label=$1
  agent_prefix=$2
  default_host_path=$3
  config_dir_name=$4

  agent_specific_config_var=${agent_prefix}_CONFIG
  agent_specific_host_var=${agent_prefix}_CONFIG_HOST_PATH
  agent_specific_config=${!agent_specific_config_var:-}
  agent_specific_host=${!agent_specific_host_var:-}

  agent_mode=${agent_specific_config:-${AGENT_CONFIG:-vm}}
  agent_host_path=$(firebreak_doctor_resolve_host_dir "${agent_specific_host:-${AGENT_CONFIG_HOST_PATH:-$default_host_path}}")

  case "$agent_mode" in
    host)
      printf '%s|%s|%s|%s\n' "$agent_label" "$agent_mode" "$agent_host_path" "$agent_specific_config_var"
      ;;
    workspace)
      printf '%s|%s|%s|%s\n' "$agent_label" "$agent_mode" "$(firebreak_doctor_workspace_config_path "$config_dir_name")" "$agent_specific_config_var"
      ;;
    vm)
      printf '%s|%s|%s|%s\n' "$agent_label" "$agent_mode" "/var/lib/dev/$config_dir_name" "$agent_specific_config_var"
      ;;
    fresh)
      printf '%s|%s|%s|%s\n' "$agent_label" "$agent_mode" "/run/agent-config-fresh" "$agent_specific_config_var"
      ;;
    *)
      printf '%s|%s|%s|%s\n' "$agent_label" "invalid" "$agent_mode" "$agent_specific_config_var"
      ;;
  esac
}

firebreak_doctor_command() {
  doctor_output=text
  doctor_verbose=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        doctor_output=json
        shift
        ;;
      --verbose)
        doctor_verbose=1
        shift
        ;;
      *)
        firebreak_doctor_usage
        ;;
    esac
  done

  firebreak_load_project_config

  cwd_whitespace=no
  case "$PWD" in
    *[[:space:]]*)
      cwd_whitespace=yes
      ;;
  esac

  launch_mode=${FIREBREAK_LAUNCH_MODE:-run}
  git_common_dir=$(firebreak_doctor_git_common_dir)
  primary_checkout=$(firebreak_doctor_primary_checkout_state "$git_common_dir")
  host_platform=$(firebreak_doctor_host_platform)
  local_runtime=$(firebreak_doctor_local_runtime)
  if [ "$local_runtime" = "qemu" ]; then
    kvm_state=$(firebreak_doctor_detect_kvm)
  else
    kvm_state="not-applicable"
  fi

  IFS='|' read -r codex_label codex_mode codex_path codex_source_var <<EOF
$(firebreak_doctor_resolve_agent_state "codex" "CODEX" "$HOME/.codex" ".codex")
EOF
  IFS='|' read -r claude_label claude_mode claude_path claude_source_var <<EOF
$(firebreak_doctor_resolve_agent_state "claude-code" "CLAUDE" "$HOME/.claude" ".claude")
EOF
  : "$codex_label" "$codex_source_var" "$claude_label" "$claude_source_var"

  if [ "$doctor_output" = "json" ]; then
    verbose_json_fields=""
    if [ "$doctor_verbose" = "1" ]; then
      verbose_json_fields=$(cat <<EOF
,
  "details": {
    "cwd": "$(firebreak_doctor_json_escape "$PWD")",
    "project_root_source": "$(firebreak_doctor_json_escape "$FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE")",
    "git_common_dir": "$(firebreak_doctor_json_escape "${git_common_dir:-unknown}")",
    "ignored_keys": [$(firebreak_doctor_json_array "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS")]
  }
EOF
)
    fi

    cat <<EOF
{
  "project_root": "$(firebreak_doctor_json_escape "$FIREBREAK_RESOLVED_PROJECT_ROOT")",
  "project_root_source": "$(firebreak_doctor_json_escape "$FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE")",
  "project_config_file": "$(firebreak_doctor_json_escape "$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE")",
  "project_config_source": "$(firebreak_doctor_json_escape "$FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE")",
  "host_platform": "$(firebreak_doctor_json_escape "$host_platform")",
  "local_runtime": "$(firebreak_doctor_json_escape "$local_runtime")",
  "cwd": "$(firebreak_doctor_json_escape "$PWD")",
  "cwd_whitespace": $([ "$cwd_whitespace" = "yes" ] && printf 'true' || printf 'false'),
  "launch_mode": "$(firebreak_doctor_json_escape "$launch_mode")",
  "git_common_dir": "$(firebreak_doctor_json_escape "${git_common_dir:-unknown}")",
  "primary_checkout": "$(firebreak_doctor_json_escape "$primary_checkout")",
  "kvm": "$(firebreak_doctor_json_escape "$kvm_state")",
  "ignored_config_keys": [$(firebreak_doctor_json_array "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS")],
  "agents": {
    "codex": {
      "mode": "$(firebreak_doctor_json_escape "$codex_mode")",
      "path": "$(firebreak_doctor_json_escape "$codex_path")"
    },
    "claude-code": {
      "mode": "$(firebreak_doctor_json_escape "$claude_mode")",
      "path": "$(firebreak_doctor_json_escape "$claude_path")"
    }
  }$verbose_json_fields
}
EOF
    exit 0
  fi

  printf 'Firebreak Doctor\n\n'
  printf 'Summary\n'
  firebreak_doctor_report_line "project_root" "$FIREBREAK_RESOLVED_PROJECT_ROOT"
  firebreak_doctor_report_line "project_config" "${FIREBREAK_RESOLVED_PROJECT_CONFIG_SOURCE}: ${FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE}"
  firebreak_doctor_report_line "host_platform" "$host_platform"
  firebreak_doctor_report_line "local_runtime" "$local_runtime"
  firebreak_doctor_report_line "launch_mode" "$launch_mode"
  firebreak_doctor_report_line "cwd_whitespace" "$cwd_whitespace"
  firebreak_doctor_report_line "primary_checkout" "$primary_checkout"
  firebreak_doctor_report_line "kvm" "$kvm_state"
  firebreak_doctor_report_line "codex_config" "$codex_mode ($codex_path)"
  firebreak_doctor_report_line "claude_config" "$claude_mode ($claude_path)"

  if [ "$doctor_verbose" = "1" ]; then
    printf '\nDetails\n'
    firebreak_doctor_report_line "project_root_source" "$FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE"
    firebreak_doctor_report_line "cwd" "$PWD"
    firebreak_doctor_report_line "git_common_dir" "${git_common_dir:-unknown}"
    firebreak_doctor_report_line "ignored_keys" "${FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS:-none}"
  fi

  printf '\nSuggested next steps\n'
  if [ "$cwd_whitespace" = "yes" ]; then
    printf '%s\n' "- Move the workspace to a path without whitespace before local VM launch."
  fi
  case "$kvm_state" in
    ok)
      :
      ;;
    not-applicable)
      :
      ;;
    *)
      printf '%s\n' "- Fix /dev/kvm access if you want validation suites that require KVM to pass instead of blocking."
      ;;
  esac
  case "$local_runtime" in
    unsupported-intel-mac)
      printf '%s\n' "- Firebreak local support on macOS is Apple Silicon only. Use an Apple Silicon Mac or a supported Linux host."
      ;;
    unsupported-host)
      printf '%s\n' "- Firebreak local workloads currently require Linux or Apple Silicon macOS."
      ;;
  esac
  if [ "$primary_checkout" = "no" ]; then
    printf '%s\n' "- Run task creation from the repository primary checkout if you need 'firebreak internal task create'."
  fi
  if [ -n "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" ]; then
    printf '%s\n' "- Remove unsupported keys from .firebreak.env or keep them in the shell environment instead."
  fi
  if [ "$cwd_whitespace" != "yes" ] && [ "$primary_checkout" != "no" ] && [ -z "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" ] && { [ "$kvm_state" = "ok" ] || [ "$kvm_state" = "not-applicable" ]; }; then
    printf '%s\n' "- No obvious launch blockers detected."
  fi
}
