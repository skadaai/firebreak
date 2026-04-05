{ config, lib, pkgs, renderTemplate, runtimeBackends, ... }:
let
  cfg = config.workloadVm;
  backendSpec = runtimeBackends.specFor cfg.runtimeBackend;
  devHome = "/var/lib/${cfg.devUser}";
  hostMetaFsType = backendSpec.localHostMetaFsType;

  scriptVars = {
    "@AGENT_VM_NAME@" = cfg.name;
    "@BASH@" = "${pkgs.bashInteractive}/bin/bash";
    "@BRANDING_NAME@" = cfg.brandingName;
    "@BRANDING_TAGLINE@" = cfg.brandingTagline;
    "@CAT@" = "${pkgs.coreutils}/bin/cat";
    "@CHOWN@" = "${pkgs.coreutils}/bin/chown";
    "@COMMAND_SHELL_INIT_FILE@" = cfg.commandShellInitFile;
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_COMMAND@" = if cfg.defaultCommand == null then "" else cfg.defaultCommand;
    "@AGENT_COMMAND_FILE@" = cfg.workerCommandFile;
    "@AGENT_EXEC_OUTPUT_MOUNT@" = cfg.workerExecOutputMount;
    "@AGENT_TOOLS_ENABLED@" = if cfg.toolRuntimesEnabled then "1" else "0";
    "@AGENT_TOOLS_MOUNT@" = cfg.toolRuntimesMount;
    "@AGENT_SESSION_MODE_FILE@" = cfg.workerSessionModeFile;
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
    "@ID@" = "${pkgs.coreutils}/bin/id";
    "@GROUPMOD@" = "${pkgs.shadow}/bin/groupmod";
    "@MKDIR@" = "${pkgs.coreutils}/bin/mkdir";
    "@SHARED_STATE_ROOT_ENABLED@" = if cfg.sharedStateRoots.enable then "1" else "0";
    "@SHARED_STATE_ROOT_FRESH_ROOT@" = cfg.sharedStateRoots.freshRoot;
    "@SHARED_STATE_ROOT_HOST_MOUNT@" = cfg.sharedStateRoots.hostMount;
    "@SHARED_STATE_ROOT_MOUNTED_FLAG@" = cfg.sharedStateRoots.mountedFlag;
    "@SHARED_STATE_ROOT_VM_ROOT@" = cfg.sharedStateRoots.vmRoot;
    "@SHARED_CREDENTIAL_SLOTS_ENABLED@" = if cfg.sharedCredentialSlots.enable then "1" else "0";
    "@SHARED_CREDENTIAL_SLOTS_HOST_MOUNT@" = cfg.sharedCredentialSlots.hostMount;
    "@SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG@" = cfg.sharedCredentialSlots.mountedFlag;
    "@PYTHON3@" = "${pkgs.python3}/bin/python3";
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@RUNUSER@" = "${pkgs.util-linux}/bin/runuser";
    "@SHARED_AGENT_WRAPPER_BIN_DIR@" = cfg.sharedToolWrapperBinDir;
    "@USERMOD@" = "${pkgs.shadow}/bin/usermod";
    "@WORKER_BRIDGE_ENABLED@" = if cfg.workerBridgeEnabled then "1" else "0";
    "@WORKER_BRIDGE_MOUNT@" = cfg.workerBridgeMount;
    "@WORKER_KINDS_FILE@" = cfg.workerKindsFile;
    "@WORKER_LOCAL_HELPER@" = "firebreak-worker-local-helper";
    "@WORKER_LOCAL_STATE_DIR@" = cfg.workerLocalStateDir;
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
  configureRuntimeNetworkScript = pkgs.writeShellScript "configure-runtime-network"
    (renderTemplate scriptVars ./guest/configure-runtime-network.sh);
  firebreakWorkerEngineScript = pkgs.writeShellScript "firebreak-worker-engine"
    (builtins.readFile ../../base/host/firebreak-worker.sh);
  firebreakWorkerEngineRuntimeInputs = with pkgs; [
    bash
    coreutils
    findutils
    gawk
    gnused
    python3
  ];
  firebreakWorkerLocalHelper = pkgs.writeShellApplication {
    name = "firebreak-worker-local-helper";
    runtimeInputs = firebreakWorkerEngineRuntimeInputs;
    text = renderTemplate (scriptVars // {
      "@WORKER_ENGINE_SCRIPT@" = "${firebreakWorkerEngineScript}";
    }) ./guest/firebreak-worker-local-helper.sh;
  };
  firebreakWorkerBridgeCli = pkgs.writeShellApplication {
    name = "firebreak";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      python3
    ];
    text = renderTemplate scriptVars ./guest/firebreak-worker-cli.sh;
  };
  devConsoleStartScript = pkgs.writeShellScript "dev-console-start"
    (renderTemplate scriptVars ./guest/dev-console-start.sh);
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  config = {
    workloadVm.requiredCapabilities = [
      "interactive-console"
      "local-networking"
      "workspace-share"
      "host-meta-share"
    ];

    users.users.root.password = "";
    users.users.${cfg.devUser}.password = "";

    networking.useDHCP = lib.mkForce (cfg.runtimeBackend != "cloud-hypervisor");

    fileSystems.${cfg.hostMetaMount} = {
      device = "hostmeta";
      fsType = hostMetaFsType;
      options = [
        "defaults"
        "ro"
        "x-systemd.after=systemd-modules-load.service"
      ];
    };
    fileSystems."/nix/.ro-store" = lib.mkIf (cfg.runtimeBackend != "vfkit") {
      device = "ro-store";
      fsType = "virtiofs";
      options = [
        "defaults"
        "ro"
        "x-systemd.after=systemd-modules-load.service"
      ];
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

    systemd.services.configure-runtime-network = lib.mkIf (cfg.runtimeBackend == "cloud-hypervisor") {
      description = "Configure runtime networking for the local Cloud Hypervisor backend";
      wantedBy = [ "multi-user.target" ];
      before = [ "dev-console.service" ] ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      after = [ "prepare-agent-session.service" ];
      requires = [ "prepare-agent-session.service" ];

      path = with pkgs; [
        coreutils
        gawk
        iproute2
      ];

      serviceConfig = {
        ExecStart = configureRuntimeNetworkScript;
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services.dev-bootstrap = lib.mkIf bootstrapEnabled {
      after = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service";
      requires = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service";
    };

    systemd.services."serial-getty@ttyS0".enable = false;

    environment.systemPackages = lib.mkIf cfg.workerBridgeEnabled [
      firebreakWorkerBridgeCli
      firebreakWorkerLocalHelper
    ];

    systemd.services.dev-console = {
      description = "Interactive dev shell on ttyS0";
      wantedBy = [ "multi-user.target" ];
      after = [ "adopt-host-identity.service" "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "adopt-host-identity.service" "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      wants = [ ];
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

    microvm.extraArgsScript = lib.optionalString (cfg.runtimeBackend != "vfkit") "${runtimeExtraArgsScript}";

    workloadVm.runtimeManagedRoStore = cfg.runtimeBackend != "vfkit";
  };
}
