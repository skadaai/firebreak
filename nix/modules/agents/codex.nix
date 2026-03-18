{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_CONFIG_DIR_FILE@" = cfg.agentConfigDirFile;
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault "firebreak-codex";
      agentConfigEnabled = true;
      agentConfigDirName = ".codex";
      agentCommand = "codex";
      extraSystemPackages = with pkgs; [
        bun
        git
        nodejs
      ];
      bootstrapPackages = with pkgs; [
        bun
        coreutils
      ];
      bootstrapScript = renderTemplate scriptVars ../../../scripts/codex-bootstrap.sh;
      shellInit = renderTemplate scriptVars ../../../scripts/codex-shell-init.sh;
    };
  };
}
