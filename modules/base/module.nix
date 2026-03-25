{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  agentConfigVmDir = "${devHome}/${cfg.agentConfigDirName}";

  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_CONFIG_DIR_FILE@" = cfg.agentConfigDirFile;
    "@AGENT_CONFIG_DIR_NAME@" = cfg.agentConfigDirName;
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
  };

  baseShellInit = renderTemplate scriptVars ./guest/shell-init.sh;
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  options.agentVm = with lib; {
    name = mkOption {
      type = types.str;
      default = "agent-vm";
      description = "MicroVM hostname and primary identity.";
    };

    brandingName = mkOption {
      type = types.str;
      default = "Skada Firebreak";
      description = "Human-facing product name printed in the interactive guest session.";
    };

    brandingTagline = mkOption {
      type = types.str;
      default = "reliable isolation for high-trust automation";
      description = "Short startup tagline printed in the interactive guest session.";
    };

    devUser = mkOption {
      type = types.str;
      default = "dev";
      description = "Interactive development user inside the MicroVM.";
    };

    workspaceMount = mkOption {
      type = types.str;
      default = "/workspace";
      description = "Guest path where the launch-time host working directory is mounted.";
    };

    hostMetaMount = mkOption {
      type = types.str;
      default = "/run/microvm-host-meta";
      description = "Guest path for the runtime metadata share used to communicate the launch directory.";
    };

    startDirFile = mkOption {
      type = types.str;
      default = "/run/microvm-start-dir";
      description = "World-readable file containing the resolved guest start directory.";
    };

    agentConfigEnabled = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the VM resolves a shared per-agent config directory for the current session.";
    };

    agentConfigDirName = mkOption {
      type = types.str;
      default = ".agent";
      description = "Directory name used for workspace/vm agent config resolution.";
    };

    agentConfigHostMount = mkOption {
      type = types.str;
      default = "/run/agent-config-host";
      description = "Guest path used for an optional host-provided agent config share.";
    };

    agentConfigDirFile = mkOption {
      type = types.str;
      default = "/run/agent-config-dir";
      description = "World-readable file containing the resolved agent config directory for the current session.";
    };

    agentConfigFreshDir = mkOption {
      type = types.str;
      default = "/run/agent-config-fresh";
      description = "Guest path used for fresh ephemeral agent config sessions.";
    };

    agentSessionModeFile = mkOption {
      type = types.str;
      default = "/run/agent-session-mode";
      description = "World-readable file containing the requested interactive session mode.";
    };

    agentCommandFile = mkOption {
      type = types.str;
      default = "/run/agent-command";
      description = "World-readable file containing the agent command selected for the current session.";
    };

    agentExecOutputMount = mkOption {
      type = types.str;
      default = "/run/agent-exec-output";
      description = "Guest path for a host-shared directory used to persist one-shot command stdout, stderr, and exit code.";
    };

    agentCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default agent command to launch in the interactive session.";
    };

    agentPromptCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command used to start a non-interactive agent session from FIREBREAK_AGENT_PROMPT.";
    };

    agentPromptFile = mkOption {
      type = types.str;
      default = "/run/agent-prompt";
      description = "World-readable file containing the initial prompt for non-interactive agent execution.";
    };

    varVolumeSizeMiB = mkOption {
      type = types.ints.positive;
      default = 2048;
      description = "Size of the persistent /var volume in MiB.";
    };

    memoryMiB = mkOption {
      type = types.ints.positive;
      default = 1024;
      description = "Guest RAM size in MiB.";
    };

    varVolumeImage = mkOption {
      type = types.str;
      default = "${cfg.name}-var.img";
      description = "Disk image backing the persistent /var volume.";
    };

    controlSocket = mkOption {
      type = types.str;
      default = "${cfg.name}.socket";
      description = "Control socket path for the MicroVM runner.";
    };

    macAddress = mkOption {
      type = types.str;
      default =
        let
          hash = builtins.hashString "sha256" cfg.name;
        in
        "02:${builtins.substring 0 2 hash}:${builtins.substring 2 2 hash}:${builtins.substring 4 2 hash}:${builtins.substring 6 2 hash}:${builtins.substring 8 2 hash}";
      description = "Stable MAC address for the MicroVM network interface.";
    };

    extraSystemPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional system packages installed inside the VM.";
    };

    runtimeExtraArgs = mkOption {
      type = types.lines;
      default = "";
      description = "Extra runtime QEMU arguments emitted by the declared runner.";
    };

    shellInit = mkOption {
      type = types.lines;
      default = "";
      description = "Extra interactive Bash initialization appended after the base shell helper.";
    };

    bootstrapPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Packages added to PATH for the optional bootstrap service.";
    };

    bootstrapScript = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = "Optional oneshot bootstrap script that runs before the console starts.";
    };

    workerBridgeEnabled = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the guest exposes the Firebreak worker bridge surface for host-brokered worker requests.";
    };

    workerBridgeMount = mkOption {
      type = types.str;
      default = "/run/firebreak-worker-bridge";
      description = "Guest path for the optional host-shared worker bridge request-response directory.";
    };
  };

  config = {
    networking.hostName = cfg.name;
    networking.useDHCP = true;
    system.stateVersion = "26.05";

    users.groups.${cfg.devUser} = { };
    users.users.${cfg.devUser} = {
      isNormalUser = true;
      group = cfg.devUser;
      extraGroups = [ "wheel" ];
      home = devHome;
      createHome = true;
      shell = pkgs.bashInteractive;
    };

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = cfg.extraSystemPackages;

    programs.bash.interactiveShellInit = ''
      ${baseShellInit}
      ${cfg.shellInit}
    '';

    systemd.services.dev-bootstrap = lib.mkIf bootstrapEnabled {
      description = "Install persistent developer tools before login";
      wantedBy = [ "multi-user.target" ];
      before = [ "getty.target" "serial-getty@ttyS0.service" ];
      after = [ "local-fs.target" "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };

      path = cfg.bootstrapPackages;
      script = cfg.bootstrapScript;
    };

    fileSystems.${cfg.workspaceMount} = {
      device = "hostcwd";
      fsType = "virtiofs";
      options = [
        "defaults"
        "x-systemd.after=systemd-modules-load.service"
      ];
    };

    microvm = {
      mem = cfg.memoryMiB;
      interfaces = [ {
        type = "user";
        id = "vm-user";
        mac = cfg.macAddress;
      } ];
      volumes = [ {
        mountPoint = "/var";
        image = cfg.varVolumeImage;
        size = cfg.varVolumeSizeMiB;
      } ];
      shares = [ {
        # use proto = "virtiofs" for MicroVMs that are started by systemd
        proto = "9p";
        tag = "ro-store";
        # a host's /nix/store will be picked up so that no
        # squashfs/erofs will be built for it.
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      } ];

      hypervisor = "qemu";
      socket = cfg.controlSocket;
    };
  };
}
