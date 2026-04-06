{ config, lib, pkgs, renderTemplate, runtimeBackends, ... }:
let
  cfg = config.workloadVm;
  backendSpec = runtimeBackends.specFor cfg.runtimeBackend;
  devHome = "/var/lib/${cfg.devUser}";
  localBin =
    if cfg.toolRuntimesEnabled then
      "${cfg.toolRuntimesMount}/.local/bin"
    else
      "${devHome}/.local/bin";
  sharedStateRootsEnvFile = "${cfg.hostMetaMount}/firebreak-shared-state.env";
  renderCredentialFileBindings = bindings:
    lib.concatStringsSep "\n" (map
      (binding: "${binding.slotPath}\t${binding.runtimePath}\t${if binding.required then "1" else "0"}")
      bindings);
  renderCredentialEnvBindings = bindings:
    lib.concatStringsSep "\n" (map
      (binding: "${binding.slotPath}\t${binding.envVar}\t${if binding.required then "1" else "0"}")
      bindings);
  renderCredentialHelperBindings = bindings:
    lib.concatStringsSep "\n" (map
      (binding: "${binding.slotPath}\t${binding.helperName}\t${binding.envVar}\t${if binding.required then "1" else "0"}")
      bindings);
  renderShellArray = values:
    lib.concatMapStringsSep "\n" (value: "  ${lib.escapeShellArg value}") values;
  resolveStateRootScript = pkgs.writeShellScript "firebreak-resolve-state-root"
    (renderTemplate {
      "@FIREBREAK_SHARED_STATE_ROOT_LIB@" = builtins.readFile ./guest/shared-state-roots.sh;
    } ./guest/resolve-state-root.sh);
  sharedToolWrapperPackages = lib.mapAttrsToList
    (wrapperName: wrapper:
      pkgs.writeShellScriptBin wrapperName
        (renderTemplate {
          "@FIREBREAK_SHARED_STATE_ROOT_LIB@" = builtins.readFile ./guest/shared-state-roots.sh;
          "@FIREBREAK_SHARED_CREDENTIAL_SLOT_LIB@" = builtins.readFile ./guest/shared-credential-slots.sh;
          "@WRAPPER_NAME@" = wrapperName;
          "@WRAPPER_DISPLAY_NAME@" = wrapper.displayName;
          "@REAL_BIN_NAME@" = wrapper.realBinName;
          "@REAL_BIN_PATH@" = wrapper.realBinPath;
          "@REAL_BIN_TOOLS_FALLBACK@" = "${cfg.toolRuntimesMount}/.local/bin/${wrapper.realBinName}";
          "@REAL_BIN_HOME_FALLBACK@" = "${devHome}/.local/bin/${wrapper.realBinName}";
          "@SPECIFIC_STATE_MODE_VAR@" = "${wrapper.selectorPrefix}_STATE_MODE";
          "@STATE_SUBDIR@" = wrapper.configSubdir;
          "@CONFIG_ENV_EXPORTS@" = wrapper.configEnvExports;
          "@CREDENTIAL_SLOT_SPECIFIC_VAR@" = "${wrapper.selectorPrefix}_CREDENTIAL_SLOT";
          "@CREDENTIAL_SLOT_SUBDIR@" = wrapper.credentials.slotSubdir;
          "@CREDENTIAL_FILE_BINDINGS@" = renderCredentialFileBindings wrapper.credentials.fileBindings;
          "@CREDENTIAL_ENV_BINDINGS@" = renderCredentialEnvBindings wrapper.credentials.envBindings;
          "@CREDENTIAL_HELPER_BINDINGS@" = renderCredentialHelperBindings wrapper.credentials.helperBindings;
          "@CREDENTIAL_LOGIN_ARGS@" = renderShellArray wrapper.credentials.loginArgs;
          "@CREDENTIAL_LOGIN_MATERIALIZATION@" = wrapper.credentials.loginMaterialization;
          "@RESOLVE_STATE_ROOT_BIN@" = "${resolveStateRootScript}";
        } ./guest/shared-tool-wrapper.sh))
    cfg.sharedStateRoots.tools;
  sharedToolWrapperPackage =
    if sharedToolWrapperPackages == [ ] then
      null
    else
      pkgs.symlinkJoin {
        name = "${cfg.name}-shared-tool-wrappers";
        paths = sharedToolWrapperPackages;
      };
  sharedToolWrapperBinDir =
    if sharedToolWrapperPackage == null then
      ""
    else
      "${sharedToolWrapperPackage}/bin";
  missingRequiredCapabilities =
    builtins.filter
      (capability: !(builtins.elem capability backendSpec.capabilities))
      cfg.requiredCapabilities;

  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@START_DIR_FILE@" = cfg.startDirFile;
    "@WORKER_KINDS_FILE@" = cfg.workerKindsFile;
    "@WORKER_LOCAL_STATE_DIR@" = cfg.workerLocalStateDir;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
    "@SHARED_STATE_ROOT_ENV_EXPORTS@" = lib.optionalString cfg.sharedStateRoots.enable ''
      export FIREBREAK_SHARED_STATE_ROOT_ENABLED=1
      export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNT=${lib.escapeShellArg cfg.sharedStateRoots.hostMount}
      export FIREBREAK_SHARED_STATE_ROOT_VM_ROOT=${lib.escapeShellArg cfg.sharedStateRoots.vmRoot}
      export FIREBREAK_SHARED_STATE_ROOT_FRESH_ROOT=${lib.escapeShellArg cfg.sharedStateRoots.freshRoot}
      export FIREBREAK_SHARED_STATE_ROOT_ENV_FILE=${lib.escapeShellArg sharedStateRootsEnvFile}
      export FIREBREAK_SHARED_STATE_ROOT_HOST_MOUNTED_FLAG=${lib.escapeShellArg cfg.sharedStateRoots.mountedFlag}
      export FIREBREAK_RESOLVE_STATE_ROOT_BIN=${lib.escapeShellArg "${resolveStateRootScript}"}
    '';
    "@SHARED_CREDENTIAL_SLOT_ENV_EXPORTS@" = lib.optionalString cfg.sharedCredentialSlots.enable ''
      export FIREBREAK_SHARED_CREDENTIAL_SLOTS_ENABLED=1
      export FIREBREAK_SHARED_CREDENTIAL_SLOTS_HOST_MOUNT=${lib.escapeShellArg cfg.sharedCredentialSlots.hostMount}
      export FIREBREAK_SHARED_CREDENTIAL_SLOTS_ENV_FILE=${lib.escapeShellArg sharedStateRootsEnvFile}
      export FIREBREAK_SHARED_CREDENTIAL_SLOTS_MOUNTED_FLAG=${lib.escapeShellArg cfg.sharedCredentialSlots.mountedFlag}
    '';
    "@SHARED_TOOL_WRAPPER_ENV_EXPORTS@" = lib.optionalString (sharedToolWrapperBinDir != "") ''
      export FIREBREAK_SHARED_TOOL_WRAPPER_BIN_DIR=${lib.escapeShellArg sharedToolWrapperBinDir}
    '';
  };

  baseShellInit = renderTemplate scriptVars ./guest/shell-init.sh;
  commandShellInit = ''
    ${baseShellInit}
    ${cfg.shellInit}
  '';
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  options.workloadVm = with lib; {
    name = mkOption {
      type = types.str;
      default = "workload-vm";
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

    hostSystem = mkOption {
      type = types.str;
      default = pkgs.stdenv.hostPlatform.system;
      description = "Host platform used to build and run the MicroVM wrapper.";
    };

    guestSystem = mkOption {
      type = types.str;
      default = pkgs.stdenv.hostPlatform.system;
      description = "Guest platform used for the NixOS system inside the MicroVM.";
    };

    runtimeBackend = mkOption {
      type = types.enum runtimeBackends.supportedBackendNames;
      default = "qemu";
      description = "Private runtime backend that satisfies the profile capability contract.";
    };

    requiredCapabilities = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Runtime capabilities that must be provided by the selected backend.";
    };

    guestEgress = mkOption {
      default = { };
      description = "Rootless guest egress contract for local runtimes.";
      type = types.submodule ({ ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the workload expects outbound guest egress through the runtime.";
          };

          vsockCID = mkOption {
            type = types.ints.positive;
            default = 52;
            description = "Guest vsock CID used for Cloud Hypervisor rootless guest egress.";
          };

          proxyPort = mkOption {
            type = types.port;
            default = 3128;
            description = "Guest localhost port used for the rootless guest egress proxy.";
          };
        };
      });
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

    workerSessionModeFile = mkOption {
      type = types.str;
      default = "/run/worker-session-mode";
      description = "World-readable file containing the requested interactive session mode.";
    };

    workerCommandFile = mkOption {
      type = types.str;
      default = "/run/worker-command";
      description = "World-readable file containing the command selected for the current session.";
    };

    workerExecOutputMount = mkOption {
      type = types.str;
      default = "/run/worker-exec-output";
      description = "Guest path for a host-shared directory used to persist one-shot command stdout, stderr, and exit code.";
    };

    commandShellInitFile = mkOption {
      type = types.str;
      default = "/etc/firebreak-command-init.sh";
      description = "Guest path to the shell-init script sourced by non-interactive worker command execution.";
    };

    toolRuntimesEnabled = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the VM mounts a host-shared persistent tools directory for bootstrap-managed tool runtimes.";
    };

    runtimeManagedRoStore = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the runtime wrapper injects the read-only /nix/store share instead of relying on declared microvm shares.";
    };

    toolRuntimesMount = mkOption {
      type = types.str;
      default = "/run/tool-runtimes-host";
      description = "Guest path for an optional host-shared directory used to persist bootstrap-managed tool runtimes across VM launches.";
    };

    defaultCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default command to launch in the interactive session.";
    };

    promptCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command used to start a non-interactive worker session from FIREBREAK_AGENT_PROMPT.";
    };

    promptFile = mkOption {
      type = types.str;
      default = "/run/worker-prompt";
      description = "World-readable file containing the initial prompt for non-interactive worker execution.";
    };

    sharedStateRoots = mkOption {
      default = { };
      description = "Shared state-root contract for sandboxes and dedicated workloads.";
      type = types.submodule ({ ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the VM exposes the shared state-root contract.";
          };

          hostMount = mkOption {
            type = types.str;
            default = "/run/firebreak-state-root";
            description = "Guest path used for the shared host-backed state root.";
          };

          vmRoot = mkOption {
            type = types.str;
            default = "${devHome}/.firebreak";
            description = "Guest root used for persistent VM-local state directories.";
          };

          freshRoot = mkOption {
            type = types.str;
            default = "/run/firebreak-state-fresh";
            description = "Guest root used for fresh ephemeral state directories.";
          };

          mountedFlag = mkOption {
            type = types.str;
            default = "/run/firebreak-shared-state-root-mounted";
            description = "Guest file used to indicate that the shared host state root is mounted.";
          };

          tools = mkOption {
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

                realBinPath = mkOption {
                  type = types.str;
                  default = "";
                  description = "Optional absolute path to the real binary when it does not live in the standard local-bin locations.";
                };

                selectorPrefix = mkOption {
                  type = types.str;
                  description = "Prefix for Firebreak selector vars such as CODEX or CLAUDE.";
                };

                configSubdir = mkOption {
                  type = types.str;
                  description = "Stable subdirectory name inside the resolved shared state root.";
                };

                configEnvExports = mkOption {
                  type = types.lines;
                  description = "Shell exports that map the resolved state directory into tool-native env vars.";
                };

                credentials = mkOption {
                  default = { };
                  description = "Optional credential-slot adapters for this wrapper.";
                  type = types.submodule ({ ... }: {
                    options = {
                      slotSubdir = mkOption {
                        type = types.str;
                        default = name;
                        description = "Stable subdirectory name used inside the selected credential slot.";
                      };

                      fileBindings = mkOption {
                        type = types.listOf (types.submodule ({ ... }: {
                          options = {
                            slotPath = mkOption {
                              type = types.str;
                              description = "Relative file path inside the selected slot.";
                            };

                            runtimePath = mkOption {
                              type = types.str;
                              description = "Relative file path inside the resolved runtime state root.";
                            };

                            required = mkOption {
                              type = types.bool;
                              default = false;
                              description = "Whether the binding must exist when a slot is selected.";
                            };
                          };
                        }));
                        default = [ ];
                        description = "Files copied from the selected slot into the runtime state root before launch and synced back on exit.";
                      };

                      envBindings = mkOption {
                        type = types.listOf (types.submodule ({ ... }: {
                          options = {
                            slotPath = mkOption {
                              type = types.str;
                              description = "Relative file path inside the selected slot.";
                            };

                            envVar = mkOption {
                              type = types.str;
                              description = "Env var populated from the slot file content.";
                            };

                            required = mkOption {
                              type = types.bool;
                              default = false;
                              description = "Whether the binding must exist when a slot is selected.";
                            };
                          };
                        }));
                        default = [ ];
                        description = "Env vars populated from files in the selected slot.";
                      };

                      helperBindings = mkOption {
                        type = types.listOf (types.submodule ({ ... }: {
                          options = {
                            slotPath = mkOption {
                              type = types.str;
                              description = "Relative file path inside the selected slot.";
                            };

                            helperName = mkOption {
                              type = types.str;
                              description = "Generated helper script name.";
                            };

                            envVar = mkOption {
                              type = types.str;
                              description = "Env var pointing at the generated helper script.";
                            };

                            required = mkOption {
                              type = types.bool;
                              default = false;
                              description = "Whether the binding must exist when a slot is selected.";
                            };
                          };
                        }));
                        default = [ ];
                        description = "Helper scripts that read their value from the selected slot.";
                      };

                      loginArgs = mkOption {
                        type = types.listOf types.str;
                        default = [ ];
                        description = "Native login argv prefix that should run against the selected slot.";
                      };

                      loginMaterialization = mkOption {
                        type = types.enum [ "none" "slot-root" ];
                        default = "none";
                        description = "How the native login command should target the selected slot.";
                      };
                    };
                  });
                };
              };
            }));
            default = { };
            description = "Wrapper commands generated for workloads that expose tool CLIs through the shared state-root contract.";
          };
        };
      });
    };

    sharedCredentialSlots = mkOption {
      default = { };
      description = "Optional shared host-backed credential slot root exposed to wrappers.";
      type = types.submodule ({ ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the VM exposes the shared credential-slot host mount.";
          };

          hostMount = mkOption {
            type = types.str;
            default = "/run/credential-slots-host-root";
            description = "Guest path used for the shared host-backed credential-slot root.";
          };

          mountedFlag = mkOption {
            type = types.str;
            default = "/run/firebreak-shared-credential-slots-mounted";
            description = "Guest file used to indicate that the shared credential-slot root is mounted.";
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

    varVolumeSeedImage = mkOption {
      type = types.str;
      default = "";
      description = "Optional preformatted /var image used by the runtime wrapper to seed cold instances without formatting at launch.";
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

    localPublishedHostPortsJson = mkOption {
      type = types.str;
      default = "[]";
      description = "Machine-readable host-to-guest port publishing declarations consumed by the local runtime wrapper.";
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

    bootstrapConditionScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional ExecCondition script used to skip dev-bootstrap entirely when cached tool state is already valid.";
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

    workerKindsJson = mkOption {
      type = types.str;
      default = "{}";
      description = "Machine-readable worker-kind declarations available inside the guest.";
    };

    workerKindsFile = mkOption {
      type = types.str;
      default = "/etc/firebreak-worker-kinds.json";
      description = "Guest path to the resolved worker-kind declaration file.";
    };

    workerLocalStateDir = mkOption {
      type = types.str;
      default = "${devHome}/.local/state/firebreak/worker-local";
      description = "Guest-owned state directory for guest-local process workers.";
    };

    sharedToolWrapperBinDir = mkOption {
      type = types.str;
      default = "";
      description = "Internal wrapper-bin path used to prefer generated Firebreak wrappers over raw tool binaries.";
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

    assertions = [
      {
        assertion = lib.hasPrefix "/etc/" cfg.workerKindsFile;
        message = "workloadVm.workerKindsFile must stay under /etc so Firebreak can materialize it declaratively.";
      }
      {
        assertion = missingRequiredCapabilities == [ ];
        message =
          "workloadVm.runtimeBackend `${cfg.runtimeBackend}` is missing required capabilities: "
          + lib.concatStringsSep ", " missingRequiredCapabilities;
      }
    ];

    environment.systemPackages =
      cfg.extraSystemPackages
      ++ lib.optional (sharedToolWrapperPackage != null) sharedToolWrapperPackage;

    workloadVm.sharedToolWrapperBinDir = sharedToolWrapperBinDir;

    environment.etc.${lib.removePrefix "/etc/" cfg.workerKindsFile}.text = cfg.workerKindsJson;
    environment.etc.${lib.removePrefix "/etc/" cfg.commandShellInitFile}.text = commandShellInit;

    programs.bash.interactiveShellInit = ''
      ${commandShellInit}
    '';

    systemd.services.dev-bootstrap = lib.mkIf bootstrapEnabled {
      description = "Install persistent developer tools before login";
      wantedBy = [ "multi-user.target" ];
      before = [ "getty.target" "serial-getty@ttyS0.service" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      } // lib.optionalAttrs (cfg.bootstrapConditionScript != null) {
        ExecCondition = cfg.bootstrapConditionScript;
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
      optimize.enable = true;
      mem = cfg.memoryMiB;
      storeOnDisk = !cfg.runtimeManagedRoStore;
      interfaces = lib.optional (cfg.runtimeBackend != "cloud-hypervisor") {
        type = "user";
        id = "vm-user";
        mac = cfg.macAddress;
      };
      volumes = [ {
        mountPoint = "/var";
        image = cfg.varVolumeImage;
        size = cfg.varVolumeSizeMiB;
      } ];
      shares = [ {
        # keep a declared host store share so microvm.nix can derive the guest
        # /nix/store mount logic without building a separate store disk image.
        proto = backendSpec.roStoreShareProto;
        tag = "ro-store";
        socket = "ro-store.sock";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        readOnly = true;
      } ];

      hypervisor = backendSpec.microvmHypervisor;
      socket = cfg.controlSocket;
    };
  };
}
