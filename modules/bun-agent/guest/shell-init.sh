if [ "$USER" = "@DEV_USER@" ]; then
  export BUN_INSTALL=@DEV_HOME@/.bun
  export LOCAL_BIN=@DEV_HOME@/.local/bin
  export XDG_CONFIG_HOME=@DEV_HOME@/.config
  export XDG_CACHE_HOME=@DEV_HOME@/.cache
  export XDG_STATE_HOME=@DEV_HOME@/.local/state
  export TMPDIR="$XDG_CACHE_HOME/tmp"
  export BUN_TMPDIR="$TMPDIR"
  export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install/cache"
  export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/transpiler"
  if [ -n "${FIREBREAK_MULTI_AGENT_WRAPPER_BIN_DIR:-}" ]; then
    export PATH="$FIREBREAK_MULTI_AGENT_WRAPPER_BIN_DIR:$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
  else
    export PATH="$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
  fi

  agent_config_dir=@DEV_HOME@/@AGENT_CONFIG_DIR_NAME@
  if [ -n "${AGENT_CONFIG_DIR:-}" ]; then
    agent_config_dir=$AGENT_CONFIG_DIR
  elif [ -r @AGENT_CONFIG_DIR_FILE@ ]; then
    agent_config_dir=$(cat @AGENT_CONFIG_DIR_FILE@)
  fi

  @AGENT_CONFIG_EXPORTS@
fi
