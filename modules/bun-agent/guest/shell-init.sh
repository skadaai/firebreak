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
  if [ -n "${FIREBREAK_SHARED_AGENT_WRAPPER_BIN_DIR:-}" ]; then
    export PATH="$FIREBREAK_SHARED_AGENT_WRAPPER_BIN_DIR:$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
  else
    export PATH="$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
  fi

  if [ -n "${FIREBREAK_RESOLVE_AGENT_CONFIG_BIN:-}" ]; then
    export FIREBREAK_AGENT_CONFIG_SPECIFIC_VAR='@AGENT_CONFIG_SELECTOR_VAR@'
    export FIREBREAK_AGENT_CONFIG_SUBDIR='@AGENT_CONFIG_SUBDIR@'
    export FIREBREAK_AGENT_CONFIG_DISPLAY_NAME='@AGENT_DISPLAY_NAME@'
    export FIREBREAK_AGENT_CONFIG_WORKSPACE_DIR_NAME='@AGENT_CONFIG_DIR_NAME@'
    AGENT_CONFIG_DIR=$("$FIREBREAK_RESOLVE_AGENT_CONFIG_BIN")
    export AGENT_CONFIG_DIR
  fi

  agent_config_dir=${AGENT_CONFIG_DIR:-@DEV_HOME@/.firebreak/@AGENT_CONFIG_SUBDIR@}
  @AGENT_CONFIG_EXPORTS@
fi
