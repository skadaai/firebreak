if [ "$USER" = "@DEV_USER@" ]; then
  firebreak_wait_for_environment_overlay() {
    if [ "@ENVIRONMENT_OVERLAY_ENABLED@" != "1" ]; then
      return 0
    fi

    max_polls=${FIREBREAK_ENVIRONMENT_OVERLAY_WAIT_POLLS:-1200}
    poll_sleep_seconds=${FIREBREAK_ENVIRONMENT_OVERLAY_WAIT_SLEEP_SECONDS:-0.1}
    poll_count=0

    while [ "$poll_count" -lt "$max_polls" ]; do
      if [ -e "@ENVIRONMENT_OVERLAY_ERROR_FLAG@" ]; then
        if [ -r "@ENVIRONMENT_OVERLAY_LOG_FILE@" ]; then
          cat "@ENVIRONMENT_OVERLAY_LOG_FILE@" >&2
        fi
        printf '%s\n' "Firebreak environment overlay failed to materialize." >&2
        exit 1
      fi

      if [ -r "@ENVIRONMENT_OVERLAY_ENV_FILE@" ] && [ -e "@ENVIRONMENT_OVERLAY_READY_FLAG@" ]; then
        return 0
      fi

      sleep "$poll_sleep_seconds"
      poll_count=$((poll_count + 1))
    done

    printf '%s\n' "timed out waiting for Firebreak environment overlay readiness: @ENVIRONMENT_OVERLAY_READY_FLAG@" >&2
    exit 1
  }

  firebreak_wait_for_environment_overlay
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
