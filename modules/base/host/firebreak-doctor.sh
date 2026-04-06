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
  value=$1
  value=$(printf '%s' "$value" | awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\n/, "\\n"); print }')
  printf '%s' "$value"
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
      printf '%s\n' "cloud-hypervisor"
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

firebreak_doctor_detect_ip_forward() {
  if ! [ -r /proc/sys/net/ipv4/ip_forward ]; then
    printf '%s\n' "unknown"
    return 0
  fi

  if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    printf '%s\n' "ok"
  else
    printf '%s\n' "disabled"
  fi
}

firebreak_doctor_detect_passwordless_sudo() {
  ip_command=$(command -v ip 2>/dev/null || true)
  iptables_command=$(command -v iptables 2>/dev/null || true)

  if [ -z "$ip_command" ] || [ -z "$iptables_command" ]; then
    printf '%s\n' "missing-tools"
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "missing-sudo"
    return 0
  fi

  if ! sudo -n "$ip_command" link show >/dev/null 2>&1; then
    printf '%s\n' "networking-denied"
    return 0
  fi

  if ! sudo -n "$iptables_command" -w -L >/dev/null 2>&1; then
    printf '%s\n' "firewall-denied"
    return 0
  fi

  printf '%s\n' "ok"
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

firebreak_doctor_state_sha256() {
  value=$1
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | cut -d' ' -f1
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$value" | shasum -a 256 | cut -d' ' -f1
    return 0
  fi

  printf '%s\n' "missing sha256 tool" >&2
  return 1
}

firebreak_doctor_workspace_state_path() {
  host_root=$1
  config_subdir=$2

  project_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
  if ! project_key=$(firebreak_doctor_state_sha256 "$project_root"); then
    printf '%s\n' "failed to resolve workspace state hash for project root: $project_root" >&2
    return 1
  fi
  project_key=$(printf '%.16s' "$project_key")
  printf '%s\n' "$host_root/workspaces/$project_key/$config_subdir"
}

firebreak_doctor_default_vm_state_root() {
  case "$(firebreak_doctor_local_runtime)" in
    cloud-hypervisor|vfkit)
      printf '%s\n' "/home/dev/.firebreak"
      ;;
    *)
      printf '%s\n' "/var/lib/dev/.firebreak"
      ;;
  esac
}

firebreak_doctor_resolve_tool_state() {
  tool_label=$1
  tool_prefix=$2
  default_host_root=$3
  state_subdir=$4

  tool_specific_state_var=${tool_prefix}_STATE_MODE
  tool_specific_state=${!tool_specific_state_var:-}

  tool_mode=${tool_specific_state:-${FIREBREAK_STATE_MODE:-host}}
  tool_host_root=$(firebreak_doctor_resolve_host_dir "${FIREBREAK_STATE_ROOT:-$default_host_root}")
  tool_host_path=$tool_host_root/$state_subdir

  case "$tool_mode" in
    host)
      printf '%s|%s|%s|%s\n' "$tool_label" "$tool_mode" "$tool_host_path" "$tool_specific_state_var"
      ;;
    workspace)
      printf '%s|%s|%s|%s\n' "$tool_label" "$tool_mode" "$(firebreak_doctor_workspace_state_path "$tool_host_root" "$state_subdir")" "$tool_specific_state_var"
      ;;
    vm)
      printf '%s|%s|%s|%s\n' "$tool_label" "$tool_mode" "$(firebreak_doctor_default_vm_state_root)/$state_subdir" "$tool_specific_state_var"
      ;;
    fresh)
      printf '%s|%s|%s|%s\n' "$tool_label" "$tool_mode" "/run/firebreak-state-fresh/$state_subdir" "$tool_specific_state_var"
      ;;
    *)
      printf '%s|%s|%s|%s\n' "$tool_label" "invalid" "$tool_mode" "$tool_specific_state_var"
      ;;
  esac
}

firebreak_doctor_resolve_credential_slot() {
  tool_label=$1
  tool_prefix=$2
  default_slot_root=$3
  slot_subdir=$4

  tool_specific_slot_var=${tool_prefix}_CREDENTIAL_SLOT
  tool_specific_slot=${!tool_specific_slot_var:-}
  selected_slot=${tool_specific_slot:-${FIREBREAK_CREDENTIAL_SLOT:-}}
  slot_root=$(firebreak_doctor_resolve_host_dir "${FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH:-$default_slot_root}")

  if [ -n "$selected_slot" ]; then
    printf '%s|%s|%s|%s\n' "$tool_label" "$selected_slot" "$slot_root/$selected_slot/$slot_subdir" "$tool_specific_slot_var"
  else
    printf '%s|%s|%s|%s\n' "$tool_label" "none" "$slot_root" "$tool_specific_slot_var"
  fi
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
  ip_forward_state="not-applicable"
  sudo_networking_state="not-applicable"
  if [ "$local_runtime" = "cloud-hypervisor" ]; then
    kvm_state=$(firebreak_doctor_detect_kvm)
    ip_forward_state=$(firebreak_doctor_detect_ip_forward)
    sudo_networking_state=$(firebreak_doctor_detect_passwordless_sudo)
  else
    kvm_state="not-applicable"
  fi

  IFS='|' read -r codex_label codex_mode codex_path codex_source_var <<EOF
$(firebreak_doctor_resolve_tool_state "codex" "CODEX" "$HOME/.firebreak" "codex")
EOF
  IFS='|' read -r claude_label claude_mode claude_path claude_source_var <<EOF
$(firebreak_doctor_resolve_tool_state "claude-code" "CLAUDE" "$HOME/.firebreak" "claude")
EOF
  IFS='|' read -r _codex_slot_label codex_slot codex_slot_path codex_slot_source_var <<EOF
$(firebreak_doctor_resolve_credential_slot "codex" "CODEX" "$HOME/.firebreak/credentials" "codex")
EOF
  IFS='|' read -r _claude_slot_label claude_slot claude_slot_path claude_slot_source_var <<EOF
$(firebreak_doctor_resolve_credential_slot "claude-code" "CLAUDE" "$HOME/.firebreak/credentials" "claude")
EOF
  : "$codex_label" "$codex_source_var" "$claude_label" "$claude_source_var" "$codex_slot_source_var" "$claude_slot_source_var"

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
  "ip_forward": "$(firebreak_doctor_json_escape "$ip_forward_state")",
  "sudo_networking": "$(firebreak_doctor_json_escape "$sudo_networking_state")",
  "ignored_config_keys": [$(firebreak_doctor_json_array "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS")],
  "tools": {
    "codex": {
      "mode": "$(firebreak_doctor_json_escape "$codex_mode")",
      "path": "$(firebreak_doctor_json_escape "$codex_path")",
      "credential_slot": "$(firebreak_doctor_json_escape "$codex_slot")",
      "credential_path": "$(firebreak_doctor_json_escape "$codex_slot_path")"
    },
    "claude-code": {
      "mode": "$(firebreak_doctor_json_escape "$claude_mode")",
      "path": "$(firebreak_doctor_json_escape "$claude_path")",
      "credential_slot": "$(firebreak_doctor_json_escape "$claude_slot")",
      "credential_path": "$(firebreak_doctor_json_escape "$claude_slot_path")"
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
  firebreak_doctor_report_line "ip_forward" "$ip_forward_state"
  firebreak_doctor_report_line "sudo_networking" "$sudo_networking_state"
  firebreak_doctor_report_line "codex_state" "$codex_mode ($codex_path)"
  firebreak_doctor_report_line "claude_state" "$claude_mode ($claude_path)"
  firebreak_doctor_report_line "codex_credentials" "$codex_slot ($codex_slot_path)"
  firebreak_doctor_report_line "claude_credentials" "$claude_slot ($claude_slot_path)"

  if [ "$doctor_verbose" = "1" ]; then
    printf '\nDetails\n'
    firebreak_doctor_report_line "project_root_source" "$FIREBREAK_RESOLVED_PROJECT_ROOT_SOURCE"
    firebreak_doctor_report_line "cwd" "$PWD"
    firebreak_doctor_report_line "git_common_dir" "${git_common_dir:-unknown}"
    firebreak_doctor_report_line "ignored_keys" "${FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS:-none}"
    firebreak_doctor_report_line "codex_selector" "$codex_source_var / $codex_slot_source_var"
    firebreak_doctor_report_line "claude_selector" "$claude_source_var / $claude_slot_source_var"
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
  case "$ip_forward_state" in
    ok|not-applicable)
      :
      ;;
    *)
      printf '%s\n' "- Enable net.ipv4.ip_forward=1 before running the local Cloud Hypervisor backend."
      ;;
  esac
  case "$sudo_networking_state" in
    ok|not-applicable)
      :
      ;;
    *)
      printf '%s\n' "- Configure passwordless sudo for Firebreak host networking commands. See guides/cloud-hypervisor-local-linux.md."
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
  if [ "$cwd_whitespace" != "yes" ] \
    && [ "$primary_checkout" != "no" ] \
    && [ -z "$FIREBREAK_PROJECT_CONFIG_IGNORED_KEYS" ] \
    && { [ "$kvm_state" = "ok" ] || [ "$kvm_state" = "not-applicable" ]; } \
    && { [ "$ip_forward_state" = "ok" ] || [ "$ip_forward_state" = "not-applicable" ]; } \
    && { [ "$sudo_networking_state" = "ok" ] || [ "$sudo_networking_state" = "not-applicable" ]; }; then
    printf '%s\n' "- No obvious launch blockers detected."
  fi
}
