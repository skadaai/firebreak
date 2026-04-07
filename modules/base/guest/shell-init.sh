if [ "$USER" = "@DEV_USER@" ]; then
  if [ -r "@ENVIRONMENT_OVERLAY_ENV_FILE@" ]; then
    # shellcheck disable=SC1090
    . "@ENVIRONMENT_OVERLAY_ENV_FILE@"
  fi
  export PS1='[\u@\h:\w]\$ '
  @SHARED_STATE_ROOT_ENV_EXPORTS@
  @SHARED_CREDENTIAL_SLOT_ENV_EXPORTS@
  @SHARED_TOOL_WRAPPER_ENV_EXPORTS@
  export PATH="@SYSTEM_BIN@:$PATH"

  if [ -n "${FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR:-}" ]; then
    export PATH="$FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR:$PATH"
  fi

  cdw() {
    target=@WORKSPACE_MOUNT@
    if [ -r @START_DIR_FILE@ ]; then
      target=$(cat @START_DIR_FILE@)
    fi
    cd "$target"
  }

  export FIREBREAK_WORKER_KINDS_FILE=@WORKER_KINDS_FILE@
  export FIREBREAK_WORKER_LOCAL_STATE_DIR=@WORKER_LOCAL_STATE_DIR@
fi
