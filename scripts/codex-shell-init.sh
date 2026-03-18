if [ "$USER" = "@DEV_USER@" ]; then
  export BUN_INSTALL=@DEV_HOME@/.bun
  export XDG_CONFIG_HOME=@DEV_HOME@/.config
  export XDG_CACHE_HOME=@DEV_HOME@/.cache
  export XDG_STATE_HOME=@DEV_HOME@/.local/state
  export PATH="$BUN_INSTALL/bin:$PATH"

  codex_config_dir=@DEV_HOME@/.codex
  if [ -n "${AGENT_CONFIG_DIR:-}" ]; then
    codex_config_dir=$AGENT_CONFIG_DIR
  elif [ -r @AGENT_CONFIG_DIR_FILE@ ]; then
    codex_config_dir=$(cat @AGENT_CONFIG_DIR_FILE@)
  fi
  export CODEX_HOME="$codex_config_dir"
  export CODEX_CONFIG_DIR="$codex_config_dir"
fi
