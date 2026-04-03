if [ "$USER" = "@DEV_USER@" ]; then
  tool_home=@DEV_HOME@
  if [ -d @AGENT_TOOLS_MOUNT@ ]; then
    tool_home=@AGENT_TOOLS_MOUNT@
  fi
  export BUN_INSTALL="$tool_home/.bun"
  export LOCAL_BIN="$tool_home/.local/bin"
  export XDG_CONFIG_HOME="$tool_home/.config"
  export XDG_CACHE_HOME="$tool_home/.cache"
  export XDG_STATE_HOME="$tool_home/.local/state"
  export TMPDIR="$XDG_CACHE_HOME/tmp"
  export BUN_TMPDIR="$TMPDIR"
  export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install/cache"
  export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/transpiler"
  export PATH="$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"

  agent_config_dir=@DEV_HOME@/@AGENT_CONFIG_DIR_NAME@
  if [ -n "${AGENT_CONFIG_DIR:-}" ]; then
    agent_config_dir=$AGENT_CONFIG_DIR
  elif [ -r @AGENT_CONFIG_DIR_FILE@ ]; then
    agent_config_dir=$(cat @AGENT_CONFIG_DIR_FILE@)
  fi

  @AGENT_CONFIG_EXPORTS@
fi
