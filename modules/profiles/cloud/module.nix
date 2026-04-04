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
    "@AGENT_EXEC_OUTPUT_MOUNT@" = cfg.agentExecOutputMount;
    "@AGENT_PROMPT_COMMAND@" = if cfg.agentPromptCommand == null then "" else cfg.agentPromptCommand;
    "@AGENT_PROMPT_FILE@" = cfg.agentPromptFile;
    "@AGENT_SESSION_MODE_FILE@" = cfg.agentSessionModeFile;
    "@BASH@" = "${pkgs.bashInteractive}/bin/bash";
    "@CAT@" = "${pkgs.coreutils}/bin/cat";
    "@CHOWN@" = "${pkgs.coreutils}/bin/chown";
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@GROUPMOD@" = "${pkgs.shadow}/bin/groupmod";
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
    "@ID@" = "${pkgs.coreutils}/bin/id";
    "@SHARED_AGENT_CONFIG_ENABLED@" = if cfg.sharedAgentConfig.enable then "1" else "0";
    "@SHARED_AGENT_CONFIG_FRESH_ROOT@" = cfg.sharedAgentConfig.freshRoot;
    "@SHARED_AGENT_CONFIG_HOST_MOUNT@" = cfg.sharedAgentConfig.hostMount;
    "@SHARED_AGENT_CONFIG_MOUNTED_FLAG@" = cfg.sharedAgentConfig.mountedFlag;
    "@SHARED_AGENT_CONFIG_VM_ROOT@" = cfg.sharedAgentConfig.vmRoot;
    "@SHARED_CREDENTIAL_SLOTS_ENABLED@" = if cfg.sharedCredentialSlots.enable then "1" else "0";
    "@SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@" = cfg.sharedCredentialSlots.hostMount;
    "@SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@" = cfg.sharedCredentialSlots.mountedFlag;
    "@RUNUSER@" = "${pkgs.util-linux}/bin/runuser";
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@SUDO@" = "${pkgs.sudo}/bin/sudo";
    "@SYSTEMCTL@" = "${pkgs.systemd}/bin/systemctl";
    "@USERMOD@" = "${pkgs.shadow}/bin/usermod";
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
  };

  runtimeExtraArgsScript = pkgs.writeShellScript "microvm-cloud-runtime-extra-args"
    ''
      ${renderTemplate scriptVars ./host/runtime-extra-args.sh}
      ${cfg.runtimeExtraArgs}
    '';
  adoptHostIdentityScript = pkgs.writeShellScript "adopt-host-identity"
    (renderTemplate scriptVars ../local/guest/adopt-host-identity.sh);
  prepareCloudSessionScript = pkgs.writeShellScript "prepare-cloud-session"
    (renderTemplate scriptVars ./guest/prepare-agent-session.sh);
  runAgentJobScript = pkgs.writeShellScript "run-agent-job"
    (renderTemplate scriptVars ./guest/run-agent-job.sh);
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  config = {
    fileSystems.${cfg.hostMetaMount} = {
      device = "hostmeta";
      fsType = "9p";
      options = qemu9pOptions ++ [ "ro" ];
    };

    systemd.services.prepare-cloud-session = {
      description = "Prepare the cloud workspace and agent session paths";
      wantedBy = [ "multi-user.target" ];
      before = [ "firebreak-agent-job.service" ];
      after = [ "local-fs.target" "adopt-host-identity.service" ];

      path = with pkgs; [
        coreutils
        util-linux
      ];

      serviceConfig = {
        ExecStart = prepareCloudSessionScript;
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services.adopt-host-identity = {
      description = "Align guest development user with the host user identity";
      wantedBy = [ "multi-user.target" ];
      before = [ "prepare-cloud-session.service" "firebreak-agent-job.service" ]
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

    systemd.services."serial-getty@ttyS0".enable = false;

    systemd.services.firebreak-agent-job = {
      description = "Run a non-interactive cloud agent job";
      wantedBy = [ "multi-user.target" ];
      after = [ "adopt-host-identity.service" "prepare-cloud-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "adopt-host-identity.service" "prepare-cloud-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";

      serviceConfig = {
        WorkingDirectory = cfg.workspaceMount;
        Type = "simple";
        ExecStart = runAgentJobScript;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    microvm.extraArgsScript = "${runtimeExtraArgsScript}";
  };
}
