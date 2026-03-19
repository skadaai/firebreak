moduleArgs:
{
  vmName,
  displayName,
  binName,
  packageSpec,
  configDirName,
  configExports,
  extraSystemPackages ? [ ],
  bootstrapPackages ? [ ],
}:
let
  inherit (moduleArgs) config lib pkgs renderTemplate;
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_BIN@" = binName;
    "@AGENT_CONFIG_DIR_FILE@" = cfg.agentConfigDirFile;
    "@AGENT_CONFIG_DIR_NAME@" = configDirName;
    "@AGENT_CONFIG_EXPORTS@" = configExports;
    "@AGENT_DISPLAY_NAME@" = displayName;
    "@AGENT_PACKAGE_SPEC@" = packageSpec;
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault vmName;
      agentConfigEnabled = true;
      agentConfigDirName = configDirName;
      agentCommand = binName;
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
      bootstrapScript = renderTemplate scriptVars ../../../scripts/bun-agent-bootstrap.sh;
      shellInit = renderTemplate scriptVars ../../../scripts/bun-agent-shell-init.sh;
    };
  };
}
