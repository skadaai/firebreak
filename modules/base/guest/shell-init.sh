if [ "$USER" = "@DEV_USER@" ]; then
  export PS1='[\u@\h:\w]\$ '
  @MULTI_AGENT_CONFIG_ENV_EXPORTS@
  @MULTI_AGENT_WRAPPER_ENV_EXPORTS@

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
fi
