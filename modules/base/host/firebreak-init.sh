firebreak_init_usage() {
  cat <<'EOF' >&2
usage:
  firebreak init [--force] [--stdout]
EOF
  exit 1
}

firebreak_render_project_config_template() {
  cat <<'EOF'
# Firebreak project defaults
#
# Real environment variables override values in this file.

# Shared config mode for local workload VMs:
AGENT_CONFIG=workspace

# Public local mode selector:
# FIREBREAK_VM_MODE=run

# Optional shared host config root when AGENT_CONFIG=host:
# AGENT_CONFIG_HOST_PATH=~/.config/firebreak-agent

# Optional per-agent overrides:
# CODEX_CONFIG=workspace
# CODEX_CONFIG_HOST_PATH=~/.codex
# CLAUDE_CONFIG=workspace
# CLAUDE_CONFIG_HOST_PATH=~/.claude
EOF
}

firebreak_init_command() {
  init_force=0
  init_stdout=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force)
        init_force=1
        shift
        ;;
      --stdout)
        init_stdout=1
        shift
        ;;
      *)
        firebreak_init_usage
        ;;
    esac
  done

  firebreak_reset_project_config_state
  firebreak_resolve_project_config_file
  target_path=$FIREBREAK_RESOLVED_PROJECT_CONFIG_FILE

  if [ "$init_stdout" = "1" ]; then
    firebreak_render_project_config_template
    exit 0
  fi

  if [ -e "$target_path" ] && [ "$init_force" != "1" ]; then
    echo "firebreak config file already exists: $target_path" >&2
    echo "use 'firebreak init --force' to overwrite it or 'firebreak doctor' to inspect the resolved state" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target_path")"
  firebreak_render_project_config_template >"$target_path"
  echo "wrote Firebreak project defaults: $target_path" >&2
}
