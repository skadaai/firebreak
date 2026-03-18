{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  codexHostConfigMount = "/run/codex-config-host";
  codexConfigDirFile = "/run/codex-config-dir";
  codexFreshConfigDir = "/run/codex-config-fresh";
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@CODEX_CONFIG_DIR_FILE@" = codexConfigDirFile;
    "@CODEX_CONFIG_HOST_MOUNT@" = codexHostConfigMount;
    "@CODEX_FRESH_CONFIG_DIR@" = codexFreshConfigDir;
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
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
      runtimeExtraArgs = renderTemplate scriptVars ../../../scripts/codex-runtime-extra-args.sh;
      shellInit = renderTemplate scriptVars ../../../scripts/codex-shell-init.sh;
    };

    systemd.services.codex-config = {
      description = "Resolve Codex config directory for the current VM session";
      wantedBy = [ "multi-user.target" ];
      before = [ "dev-console.service" ];
      after = [ "sync-host-identity.service" "link-host-cwd.service" ];
      requires = [ "sync-host-identity.service" "link-host-cwd.service" ];

      path = with pkgs; [
        coreutils
        util-linux
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };

      script = renderTemplate scriptVars ../../../scripts/codex-config-resolve.sh;
    };

    systemd.services.dev-console.after = lib.mkAfter [ "codex-config.service" ];
    systemd.services.dev-console.requires = lib.mkAfter [ "codex-config.service" ];
  };
}
