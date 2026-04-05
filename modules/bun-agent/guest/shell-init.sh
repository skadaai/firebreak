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
  if [ -n "${FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR:-}" ]; then
    export PATH="$FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR:$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
  else
    export PATH="$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
  fi

  if [ -n "${FIREBREAK_RESOLVE_STATE_ROOT_BIN:-}" ]; then
    export FIREBREAK_STATE_MODE_SPECIFIC_VAR='@STATE_MODE_SELECTOR_VAR@'
    export FIREBREAK_STATE_SUBDIR='@STATE_SUBDIR@'
    export FIREBREAK_STATE_DISPLAY_NAME='@AGENT_DISPLAY_NAME@'
    resolver_output=$("$FIREBREAK_RESOLVE_STATE_ROOT_BIN" 2>&1) && resolver_status=0 || resolver_status=$?
    if [ "$resolver_status" -ne 0 ] || [ -z "$resolver_output" ]; then
      printf '%s\n' "failed to resolve Firebreak state root via $FIREBREAK_RESOLVE_STATE_ROOT_BIN (exit $resolver_status): $resolver_output" >&2
      exit 1
    fi
    FIREBREAK_TOOL_STATE_DIR=$resolver_output
    export FIREBREAK_TOOL_STATE_DIR
  fi

  tool_state_dir=${FIREBREAK_TOOL_STATE_DIR:-@DEV_HOME@/.firebreak/@STATE_SUBDIR@}
  @STATE_ENV_EXPORTS@
fi
