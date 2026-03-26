export FIREBREAK_EXTERNAL_PROJECT="@NAME@"
export LOCAL_BIN="@LOCAL_BIN@"
export XDG_CONFIG_HOME="@XDG_CONFIG_HOME@"
export XDG_CACHE_HOME="@XDG_CACHE_HOME@"
export XDG_STATE_HOME="@XDG_STATE_HOME@"
export TMPDIR="@TMPDIR@"
export npm_config_cache="@NPM_CACHE_DIR@"
export npm_config_prefix="@DEV_HOME@/.local"
export PATH="$LOCAL_BIN:$PATH"
@LAUNCH_ENV_EXPORTS@

firebreak_refresh_cli() {
  printf "Refreshing @NAME@ CLI...\n"

  printf "Removing install state...\n"
  sudo rm -f "@DEV_HOME@/.cache/firebreak-tools/@NAME@/install-state"

  printf "Removing bootstrap ready marker...\n"
  sudo rm -f "@BOOTSTRAP_READY_MARKER@"

  printf "Removing node modules and npm cache...\n"
  sudo rm -rf "@PACKAGE_NODE_MODULES@" "@NPM_CACHE_DIR@"

  printf "Removing local binary...\n"
  sudo rm -f "@LOCAL_BIN@/@BIN_NAME@"

  printf "Restarting dev-bootstrap service...\n"
  sudo systemctl restart dev-bootstrap.service && @READY_COMMAND_NAME@
}

alias project-launch='@LAUNCH_COMMAND_NAME@'
alias project-ready='@READY_COMMAND_NAME@'
alias firebreak-refresh-cli='firebreak_refresh_cli'
@EXTRA_SHELL_INIT@
