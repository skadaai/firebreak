export FIREBREAK_EXTERNAL_PROJECT="@NAME@"
tool_home="@DEV_HOME@"
if [ -d "@AGENT_TOOLS_MOUNT@" ]; then
  tool_home="@AGENT_TOOLS_MOUNT@"
fi
export LOCAL_BIN="$tool_home/.local/bin"
export XDG_CONFIG_HOME="$tool_home/.config"
export XDG_CACHE_HOME="$tool_home/.cache"
export XDG_STATE_HOME="$tool_home/.local/state"
export TMPDIR="$XDG_CACHE_HOME/tmp"
export npm_config_cache="$XDG_CACHE_HOME/npm"
export npm_config_prefix="$tool_home/.local"
if [ -n "${FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR:-}" ]; then
  export PATH="$FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR:$LOCAL_BIN:$PATH"
else
  export PATH="$LOCAL_BIN:$PATH"
fi
@LAUNCH_ENV_EXPORTS@

if [ -r /run/firebreak-worker/worker-mode ]; then
  if worker_mode_value=$(cat /run/firebreak-worker/worker-mode); then
    export FIREBREAK_WORKER_MODE="$worker_mode_value"
  fi
fi

if [ -r /run/firebreak-worker/worker-modes ]; then
  if worker_modes_value=$(cat /run/firebreak-worker/worker-modes); then
    export FIREBREAK_WORKER_MODES="$worker_modes_value"
  fi
fi

firebreak_refresh_cli() {
  printf "Refreshing @NAME@ CLI...\n"

  printf "Removing install state...\n"
  sudo rm -f "$XDG_STATE_HOME/firebreak-node-cli/@NAME@/install-state"

  printf "Removing bootstrap ready marker...\n"
  sudo rm -f "@BOOTSTRAP_READY_MARKER@"

  printf "Removing node modules and npm cache...\n"
  sudo rm -rf "$npm_config_prefix/lib/node_modules/@PACKAGE_SPEC@" "$npm_config_cache"

  printf "Removing local binary...\n"
  sudo rm -f "$LOCAL_BIN/@BIN_NAME@"
  for upstream_name in @PROXY_LOCAL_UPSTREAM_NAMES@; do
    sudo rm -f "$LOCAL_BIN/.firebreak-upstream-$upstream_name"
  done

  printf "Restarting dev-bootstrap service...\n"
  sudo systemctl restart dev-bootstrap.service && @READY_COMMAND_NAME@
}

alias project-launch='@LAUNCH_COMMAND_NAME@'
alias project-ready='@READY_COMMAND_NAME@'
alias firebreak-refresh-cli='firebreak_refresh_cli'
@EXTRA_SHELL_INIT@
