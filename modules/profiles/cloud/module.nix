{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.workloadVm;
  devHome = cfg.devHome;

  qemu9pOptions = [
    "nofail"
    "trans=virtio"
    "version=9p2000.L"
    "msize=65536"
    "x-systemd.after=systemd-modules-load.service"
  ];

  scriptVars = {
    "@COMMAND_OUTPUT_MOUNT@" = cfg.workerExecOutputMount;
    "@TOOL_PROMPT_COMMAND@" = if cfg.promptCommand == null then "" else cfg.promptCommand;
    "@TOOL_PROMPT_FILE@" = cfg.promptFile;
    "@SESSION_MODE_FILE@" = cfg.workerSessionModeFile;
    "@BASH@" = "${pkgs.bashInteractive}/bin/bash";
    "@CAT@" = "${pkgs.coreutils}/bin/cat";
    "@CHOWN@" = "${pkgs.coreutils}/bin/chown";
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@GROUPMOD@" = "${pkgs.shadow}/bin/groupmod";
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
    "@ID@" = "${pkgs.coreutils}/bin/id";
    "@SHARED_STATE_ROOT_ENABLED@" = if cfg.sharedStateRoots.enable then "1" else "0";
    "@SHARED_STATE_ROOT_FRESH_ROOT@" = cfg.sharedStateRoots.freshRoot;
    "@SHARED_STATE_ROOT_HOST_MOUNT@" = cfg.sharedStateRoots.hostMount;
    "@SHARED_STATE_ROOT_MOUNTED_FLAG@" = cfg.sharedStateRoots.mountedFlag;
    "@SHARED_STATE_ROOT_VM_ROOT@" = cfg.sharedStateRoots.vmRoot;
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
    (renderTemplate scriptVars ./guest/prepare-worker-session.sh);
  runToolJobScript = pkgs.writeShellScript "run-tool-job"
    (renderTemplate scriptVars ./guest/run-tool-job.sh);
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  config = {
    assertions = [
      {
        assertion = cfg.runtimeBackend == "qemu";
        message = "firebreak cloud profile currently supports only the `qemu` backend.";
      }
    ];

    fileSystems.${cfg.hostMetaMount} = {
      device = "hostmeta";
      fsType = "9p";
      options = qemu9pOptions ++ [ "ro" ];
    };

    systemd.services.prepare-cloud-session = {
      description = "Prepare the cloud workspace and worker session paths";
      wantedBy = [ "multi-user.target" ];
      before = [ "firebreak-tool-job.service" ];
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
      before = [ "prepare-cloud-session.service" "firebreak-tool-job.service" ]
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

    systemd.services.firebreak-tool-job = {
      description = "Run a non-interactive cloud tool job";
      wantedBy = [ "multi-user.target" ];
      after = [ "adopt-host-identity.service" "prepare-cloud-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "adopt-host-identity.service" "prepare-cloud-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";

      serviceConfig = {
        WorkingDirectory = cfg.workspaceMount;
        Type = "simple";
        ExecStart = runToolJobScript;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    microvm.extraArgsScript = "${runtimeExtraArgsScript}";
  };
}
