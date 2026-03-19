{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  agentConfigVmDir = "${devHome}/${cfg.agentConfigDirName}";

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
    "@AGENT_CONFIG_VM_DIR@" = agentConfigVmDir;
    "@AGENT_COMMAND@" = if cfg.agentCommand == null then "" else cfg.agentCommand;
    "@AGENT_COMMAND_FILE@" = cfg.agentCommandFile;
    "@AGENT_EXEC_OUTPUT_MOUNT@" = cfg.agentExecOutputMount;
    "@AGENT_SESSION_MODE_FILE@" = cfg.agentSessionModeFile;
    "@HOST_META_MOUNT@" = cfg.hostMetaMount;
    "@ID@" = "${pkgs.coreutils}/bin/id";
    "@GROUPMOD@" = "${pkgs.shadow}/bin/groupmod";
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@USERMOD@" = "${pkgs.shadow}/bin/usermod";
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
  };

  baseShellInit = renderTemplate scriptVars ../../scripts/agent-vm-shell-init.sh;
  adoptHostIdentityScript = pkgs.writeShellScript "adopt-host-identity"
    (renderTemplate scriptVars ../../scripts/adopt-host-identity.sh);
  runtimeExtraArgsScript = pkgs.writeShellScript "microvm-runtime-extra-args"
    ''
      ${renderTemplate scriptVars ../../scripts/runtime-extra-args.sh}
      ${cfg.runtimeExtraArgs}
    '';
  prepareAgentSessionScript = pkgs.writeShellScript "prepare-agent-session"
    (renderTemplate scriptVars ../../scripts/prepare-agent-session.sh);
  devConsoleStartScript = pkgs.writeShellScript "dev-console-start"
    (renderTemplate scriptVars ../../scripts/dev-console-start.sh);
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

    varVolumeSizeMiB = mkOption {
      type = types.ints.positive;
      default = 2048;
      description = "Size of the persistent /var volume in MiB.";
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
  };

  config = {
    networking.hostName = cfg.name;
    networking.useDHCP = true;
    system.stateVersion = "26.05";

    users.users.root.password = "";
    users.groups.${cfg.devUser} = { };
    users.users.${cfg.devUser} = {
      isNormalUser = true;
      password = "";
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

    systemd.services.dev-bootstrap = lib.mkIf bootstrapEnabled {
      description = "Install persistent developer tools before login";
      wantedBy = [ "multi-user.target" ];
      before = [ "getty.target" "serial-getty@ttyS0.service" ];
      after = [ "local-fs.target" "network-online.target" "adopt-host-identity.service" ];
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

    fileSystems.${cfg.hostMetaMount} = {
      device = "hostmeta";
      fsType = "9p";
      options = qemu9pOptions ++ [ "ro" ];
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

    systemd.services.dev-console = {
      description = "Interactive dev shell on ttyS0";
      wantedBy = [ "multi-user.target" ];
      after = [ "adopt-host-identity.service" "prepare-agent-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "adopt-host-identity.service" "prepare-agent-session.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
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

    microvm = {
      extraArgsScript = "${runtimeExtraArgsScript}";
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

      # "qemu" has 9p built-in!
      hypervisor = "qemu";
      socket = cfg.controlSocket;
    };
  };
}
