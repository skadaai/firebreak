if [ "$USER" = "@DEV_USER@" ]; then
  export PS1='[\u@\h:\w]\$ '

  cdw() {
    target=@WORKSPACE_MOUNT@
    if [ -r @START_DIR_FILE@ ]; then
      target=$(cat @START_DIR_FILE@)
    fi
    cd "$target"
  }

  if [ -r @AGENT_CONFIG_DIR_FILE@ ]; then
    export AGENT_CONFIG_DIR=$(cat @AGENT_CONFIG_DIR_FILE@)
  fi

  export FIREBREAK_WORKER_KINDS_FILE=@WORKER_KINDS_FILE@
  export FIREBREAK_WORKER_LOCAL_STATE_DIR=@WORKER_LOCAL_STATE_DIR@
fi
