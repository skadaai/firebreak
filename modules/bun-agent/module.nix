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
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_CONFIG_DIR_NAME@" = configDirName;
    "@AGENT_CONFIG_EXPORTS@" = configExports;
    "@AGENT_CONFIG_SELECTOR_VAR@" = "${configSelectorPrefix}_CONFIG";
    "@AGENT_CONFIG_SUBDIR@" = configSubdir;
    "@AGENT_DISPLAY_NAME@" = displayName;
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault vmName;
      agentConfigEnabled = false;
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
        git
        nodejs
      ] ++ extraSystemPackages;
      bootstrapPackages = with pkgs; [
        bun
        coreutils
        nodejs
      ] ++ bootstrapPackages;
      bootstrapScript = renderTemplate scriptVars ./guest/bootstrap.sh;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };
  };
}
