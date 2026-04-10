if [ "$USER" = "@DEV_USER@" ]; then
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
