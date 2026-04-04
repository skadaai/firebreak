moduleArgs:
{
  vmName,
  displayName,
  binName,
  packageSpec,
  promptCommand,
  configSelectorPrefix,
  configSubdir,
  configExports,
  extraSystemPackages ? [ ],
  bootstrapPackages ? [ ],
}:
let
  inherit (moduleArgs) config lib pkgs renderTemplate;
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  configDirName = ".firebreak/${configSubdir}";
  toolsMount = cfg.agentToolsMount;
  bootstrapReadyMarker =
    if cfg.agentToolsEnabled
    then "${toolsMount}/bootstrap-ready"
    else "${devHome}/.cache/firebreak-tools/${vmName}/bootstrap-ready";
  bootstrapWaitScript = pkgs.writeShellApplication {
    name = "firebreak-bootstrap-wait";
    runtimeInputs = with pkgs; [ coreutils gnugrep ];
    text = ''
      set -eu

      ready_marker='${bootstrapReadyMarker}'
      state_path='/run/firebreak-agent/bootstrap-state.json'
      timeout_seconds=''${FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS:-300}
      elapsed_seconds=0

      case "$timeout_seconds" in
        ""|*[!0-9]*)
          echo "FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS must be a non-negative integer" >&2
          exit 1
          ;;
      esac

      while [ "$elapsed_seconds" -lt "$timeout_seconds" ]; do
        if [ -r "$ready_marker" ]; then
          exit 0
        fi
        if [ -r "$state_path" ] && grep -F -q '"status": "error"' "$state_path"; then
          cat "$state_path" >&2
          exit 1
        fi
        sleep 1
        elapsed_seconds=$((elapsed_seconds + 1))
      done

      if [ -r "$ready_marker" ]; then
        exit 0
      fi

      if [ -r "$state_path" ]; then
        cat "$state_path" >&2
      fi
      echo "timed out waiting for Firebreak bootstrap readiness marker: $ready_marker" >&2
      exit 1
    '';
  };
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_CONFIG_DIR_NAME@" = configDirName;
    "@AGENT_CONFIG_EXPORTS@" = configExports;
    "@AGENT_CONFIG_SELECTOR_VAR@" = "${configSelectorPrefix}_CONFIG";
    "@AGENT_CONFIG_SUBDIR@" = configSubdir;
    "@AGENT_DISPLAY_NAME@" = displayName;
    "@AGENT_EXEC_OUTPUT_MOUNT@" = cfg.agentExecOutputMount;
    "@AGENT_PACKAGE_SPEC@" = packageSpec;
    "@AGENT_TOOLS_MOUNT@" = toolsMount;
    "@BOOTSTRAP_READY_MARKER@" = bootstrapReadyMarker;
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault vmName;
      agentConfigEnabled = true;
      agentToolsEnabled = true;
      agentConfigDirName = configDirName;
      agentConfigSubdir = configSubdir;
      sharedAgentConfig = {
        enable = true;
        agents.${binName} = {
          displayName = displayName;
          selectorPrefix = configSelectorPrefix;
          configSubdir = configSubdir;
          configEnvExports = configExports;
        };
      };
      agentCommand = binName;
      agentPromptCommand = promptCommand;
      extraSystemPackages = with pkgs; [
        bun
        bootstrapWaitScript
        git
        nodejs
      ] ++ extraSystemPackages;
      bootstrapPackages = with pkgs; [
        bun
        coreutils
        nodejs
        util-linux
      ] ++ bootstrapPackages;
      bootstrapScript = renderTemplate scriptVars ./guest/bootstrap.sh;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };
  };
}
