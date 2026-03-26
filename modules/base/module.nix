{ config, lib, pkgs, renderTemplate, ... }:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  localBin = "${devHome}/.local/bin";
  sharedAgentConfigEnvFile = "${cfg.hostMetaMount}/firebreak-shared-agent.env";
  resolveAgentConfigScript = pkgs.writeShellScript "firebreak-resolve-agent-config"
    (builtins.readFile ./guest/resolve-agent-config.sh);
  sharedAgentWrapperPackages = lib.mapAttrsToList
    (wrapperName: wrapper:
      pkgs.writeShellScriptBin wrapperName
        (renderTemplate {
          "@WRAPPER_NAME@" = wrapperName;
          "@WRAPPER_DISPLAY_NAME@" = wrapper.displayName;
          "@REAL_BIN@" = "${localBin}/${wrapper.realBinName}";
          "@SPECIFIC_CONFIG_VAR@" = "${wrapper.selectorPrefix}_CONFIG";
          "@CONFIG_SUBDIR@" = wrapper.configSubdir;
          "@WORKSPACE_DIR_NAME@" = ".firebreak/${wrapper.configSubdir}";
          "@CONFIG_ENV_EXPORTS@" = wrapper.configEnvExports;
          "@RESOLVE_AGENT_CONFIG_BIN@" = "${resolveAgentConfigScript}";
        } ./guest/shared-agent-wrapper.sh))
    cfg.sharedAgentConfig.agents;
  sharedAgentWrapperPackage =
    if sharedAgentWrapperPackages == [ ] then
      null
    else
      pkgs.symlinkJoin {
        name = "${cfg.name}-shared-agent-wrappers";
        paths = sharedAgentWrapperPackages;
      };
  sharedAgentWrapperBinDir =
    if sharedAgentWrapperPackage == null then
      ""
    else
      "${sharedAgentWrapperPackage}/bin";

  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@AGENT_CONFIG_DIR_FILE@" = cfg.agentConfigDirFile;
    "@AGENT_CONFIG_DIR_NAME@" = cfg.agentConfigDirName;
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
    "@SHARED_AGENT_CONFIG_ENV_EXPORTS@" = lib.optionalString cfg.sharedAgentConfig.enable ''
      export FIREBREAK_SHARED_AGENT_CONFIG_ENABLED=1
      export FIREBREAK_SHARED_AGENT_CONFIG_HOST_MOUNT=${lib.escapeShellArg cfg.sharedAgentConfig.hostMount}
      export FIREBREAK_SHARED_AGENT_CONFIG_VM_ROOT=${lib.escapeShellArg cfg.sharedAgentConfig.vmRoot}
      export FIREBREAK_SHARED_AGENT_CONFIG_FRESH_ROOT=${lib.escapeShellArg cfg.sharedAgentConfig.freshRoot}
      export FIREBREAK_SHARED_AGENT_CONFIG_ENV_FILE=${lib.escapeShellArg sharedAgentConfigEnvFile}
      export FIREBREAK_SHARED_AGENT_CONFIG_HOST_MOUNTED_FLAG=${lib.escapeShellArg cfg.sharedAgentConfig.mountedFlag}
      export FIREBREAK_RESOLVE_AGENT_CONFIG_BIN=${lib.escapeShellArg "${resolveAgentConfigScript}"}
    '';
    "@SHARED_AGENT_WRAPPER_ENV_EXPORTS@" = lib.optionalString (sharedAgentWrapperBinDir != "") ''
      export FIREBREAK_SHARED_AGENT_WRAPPER_BIN_DIR=${lib.escapeShellArg sharedAgentWrapperBinDir}
    '';
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

    agentConfigSubdir = mkOption {
      type = types.str;
      default = "agent";
      description = "Stable subdirectory name used under the unified host config root.";
    };

    agentConfigDirFile = mkOption {
      type = types.str;
      default = "/run/agent-config-dir";
      description = "World-readable file containing the resolved agent config directory for the current session.";
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

    sharedAgentConfig = mkOption {
      default = { };
      description = "Shared agent config-root contract for sandboxes and dedicated workloads.";
      type = types.submodule ({ ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the VM exposes the shared agent config-root contract.";
          };

          hostMount = mkOption {
            type = types.str;
            default = "/run/agent-config-host-root";
            description = "Guest path used for the shared host-backed agent config root.";
          };

          vmRoot = mkOption {
            type = types.str;
            default = "${devHome}/.firebreak";
            description = "Guest root used for persistent VM-local agent config directories.";
          };

          freshRoot = mkOption {
            type = types.str;
            default = "/run/firebreak-agent-config-fresh";
            description = "Guest root used for fresh ephemeral agent config directories.";
          };

          mountedFlag = mkOption {
            type = types.str;
            default = "/run/firebreak-shared-agent-config-host-mounted";
            description = "Guest file used to indicate that the shared host config root is mounted.";
          };

          agents = mkOption {
            type = types.attrsOf (types.submodule ({ name, ... }: {
              options = {
                displayName = mkOption {
                  type = types.str;
                  default = name;
                  description = "Human-facing wrapper name used in diagnostics.";
                };

                realBinName = mkOption {
                  type = types.str;
                  default = name;
                  description = "Real binary name in the per-user local bin directory.";
                };

                selectorPrefix = mkOption {
                  type = types.str;
                  description = "Prefix for Firebreak selector vars such as CODEX or CLAUDE.";
                };

                configSubdir = mkOption {
                  type = types.str;
                  description = "Stable subdirectory name inside the resolved shared agent config root.";
                };

                configEnvExports = mkOption {
                  type = types.lines;
                  description = "Shell exports that map the resolved config directory into agent-native env vars.";
                };
              };
            }));
            default = { };
            description = "Wrapper commands generated for workloads that expose agent CLIs through the shared config-root contract.";
          };
        };
      });
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

    environment.systemPackages =
      cfg.extraSystemPackages
      ++ lib.optional (sharedAgentWrapperPackage != null) sharedAgentWrapperPackage;

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
