if [ "$USER" = "@DEV_USER@" ]; then
  export BUN_INSTALL=@DEV_HOME@/.bun
  export XDG_CONFIG_HOME=@DEV_HOME@/.config
  export XDG_CACHE_HOME=@DEV_HOME@/.cache
  export XDG_STATE_HOME=@DEV_HOME@/.local/state
  export PATH="$BUN_INSTALL/bin:$PATH"
fi
