{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";

  qemu9pOptions = [
    "nofail"
    "trans=virtio"
    "version=9p2000.L"
    "msize=65536"
    "x-systemd.after=systemd-modules-load.service"
  ];

  scriptVars = {
    "@AGENT_VM_NAME@" = cfg.name;
    "@BASH@" = "${pkgs.bashInteractive}/bin/bash";
    "@BRANDING_NAME@" = cfg.brandingName;
    "@BRANDING_TAGLINE@" = cfg.brandingTagline;
    "@CAT@" = "${pkgs.coreutils}/bin/cat";
    "@CHOWN@" = "${pkgs.coreutils}/bin/chown";
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_CONFIG_DIR_FILE@" = cfg.agentConfigDirFile;
    "@AGENT_CONFIG_DIR_NAME@" = cfg.agentConfigDirName;
    "@AGENT_CONFIG_ENABLED@" = if cfg.agentConfigEnabled then "1" else "0";
    "@AGENT_CONFIG_FRESH_DIR@" = cfg.agentConfigFreshDir;
    "@AGENT_CONFIG_HOST_MOUNT@" = cfg.agentConfigHostMount;
    "@AGENT_CONFIG_VM_DIR@" = "${devHome}/${cfg.agentConfigDirName}";
    "@AGENT_COMMAND@" = if cfg.agentCommand == null then "" else cfg.agentCommand;
    "@AGENT_COMMAND_FILE@" = cfg.agentCommandFile;
    "@AGENT_EXEC_OUTPUT_MOUNT@" = cfg.agentExecOutputMount;
    "@AGENT_SESSION_MODE_FILE@" = cfg.agentSessionModeFile;
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
    "@ID@" = "${pkgs.coreutils}/bin/id";
    "@GROUPMOD@" = "${pkgs.shadow}/bin/groupmod";
    "@MKDIR@" = "${pkgs.coreutils}/bin/mkdir";
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@RUNUSER@" = "${pkgs.util-linux}/bin/runuser";
    "@USERMOD@" = "${pkgs.shadow}/bin/usermod";
    "@WORKER_BRIDGE_ENABLED@" = if cfg.workerBridgeEnabled then "1" else "0";
    "@WORKER_BRIDGE_MOUNT@" = cfg.workerBridgeMount;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
  };

  adoptHostIdentityScript = pkgs.writeShellScript "adopt-host-identity"
    (renderTemplate scriptVars ./guest/adopt-host-identity.sh);
  runtimeExtraArgsScript = pkgs.writeShellScript "microvm-runtime-extra-args"
    ''
      ${renderTemplate scriptVars ./host/runtime-extra-args.sh}
      ${cfg.runtimeExtraArgs}
    '';
  prepareAgentSessionScript = pkgs.writeShellScript "prepare-agent-session"
    (renderTemplate scriptVars ./guest/prepare-agent-session.sh);
  firebreakWorkerBridgeCli = pkgs.writeShellApplication {
    name = "firebreak";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      python3
    ];
    text = renderTemplate scriptVars ./guest/firebreak-worker-bridge-cli.sh;
  };
  devConsoleStartScript = pkgs.writeShellScript "dev-console-start"
    (renderTemplate scriptVars ./guest/dev-console-start.sh);
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  config = {
    users.users.root.password = "";
    users.users.${cfg.devUser}.password = "";

    fileSystems.${cfg.hostMetaMount} = {
      device = "hostmeta";
      fsType = "9p";
      options = qemu9pOptions ++ [ "ro" ];
    };

    systemd.services.adopt-host-identity = {
      description = "Align guest development user with the host user identity";
      wantedBy = [ "multi-user.target" ];
      before = [ "prepare-agent-session.service" "serial-getty@ttyS0.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      after = [ "local-fs.target" ];

      path = with pkgs; [
        coreutils
        shadow
      ];

      serviceConfig = {
        ExecStart = adoptHostIdentityScript;
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services.prepare-agent-session = {
      description = "Prepare the workspace and agent session paths";
      wantedBy = [ "multi-user.target" ];
      before = [ "dev-console.service" ];
      after = [ "local-fs.target" "adopt-host-identity.service" ];

      path = with pkgs; [
        coreutils
        util-linux
      ];

      serviceConfig = {
        ExecStart = prepareAgentSessionScript;
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services."serial-getty@ttyS0".enable = false;

    environment.systemPackages = lib.mkIf cfg.workerBridgeEnabled [ firebreakWorkerBridgeCli ];

    systemd.services.dev-console = {
      description = "Interactive dev shell on ttyS0";
      wantedBy = [ "multi-user.target" ];
      after = [ "adopt-host-identity.service" "prepare-agent-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "adopt-host-identity.service" "prepare-agent-session.service" ];
      wants = lib.optional bootstrapEnabled "dev-bootstrap.service";
      conflicts = [ "serial-getty@ttyS0.service" ];

      serviceConfig = {
        User = cfg.devUser;
        WorkingDirectory = devHome;
        StandardInput = "tty-force";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/ttyS0";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        Restart = "on-failure";
        RestartSec = 0;
        Type = "idle";
        ExecStart = devConsoleStartScript;
      };
    };

    microvm.extraArgsScript = "${runtimeExtraArgsScript}";
  };
}
