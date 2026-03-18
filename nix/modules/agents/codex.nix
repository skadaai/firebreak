{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault "codex-vm";
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
