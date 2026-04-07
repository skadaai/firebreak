{ config, lib, pkgs, renderTemplate, runtimeBackends, ... }:
let
  cfg = config.workloadVm;
  backendSpec = runtimeBackends.specFor cfg.runtimeBackend;
  devHome = cfg.devHome;
  runtimeHostMount = "/run/firebreak-host-runtime";
  hostCwdShareSocket = "hostcwd.sock";
  hostRuntimeShareSocket = "hostruntime.sock";
  sharedStateRootShareSocket = "hoststateroot.sock";
  sharedCredentialSlotsShareSocket = "hostcredentialslots.sock";
  agentToolsShareSocket = "hostagenttools.sock";
  hostMetaMount = "${runtimeHostMount}/meta";
  workerExecOutputMount = "${runtimeHostMount}/exec-output";
  workerBridgeMount = "${runtimeHostMount}/worker-bridge";
  hostMetaFsType = backendSpec.localHostMetaFsType;

  baseScriptVars = {
    "@AGENT_VM_NAME@" = cfg.name;
    "@BASH@" = "${pkgs.bashInteractive}/bin/bash";
    "@BRANDING_NAME@" = cfg.brandingName;
    "@BRANDING_TAGLINE@" = cfg.brandingTagline;
    "@CAT@" = "${pkgs.coreutils}/bin/cat";
    "@CHOWN@" = "${pkgs.coreutils}/bin/chown";
    "@COMMAND_SHELL_INIT_FILE@" = cfg.commandShellInitFile;
    "@COLD_EXEC_BOOTSTRAP_WAIT_ENABLED@" = if cfg.coldExecBootstrapWaitEnable then "1" else "0";
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
    "@SETPRIV@" = "${pkgs.util-linux}/bin/setpriv";
    "@RUNTIME_BACKEND@" = cfg.runtimeBackend;
    "@SHARED_AGENT_WRAPPER_BIN_DIR@" = cfg.sharedToolWrapperBinDir;
    "@USERMOD@" = "${pkgs.shadow}/bin/usermod";
    "@WORKER_BRIDGE_ENABLED@" = if cfg.workerBridgeEnabled then "1" else "0";
    "@WORKER_BRIDGE_MOUNT@" = cfg.workerBridgeMount;
    "@WORKER_KINDS_FILE@" = cfg.workerKindsFile;
    "@WORKER_LOCAL_HELPER@" = "firebreak-worker-local-helper";
    "@WORKER_LOCAL_STATE_DIR@" = cfg.workerLocalStateDir;
    "@WORKSPACE_MOUNT@" = cfg.workspaceMount;
    "@NETWORK_MAC@" = cfg.macAddress;
  };
  renderedAgentCommandRequestLib = renderTemplate baseScriptVars ./guest/agent-command-request.sh;
  renderedAgentCommandStateLib = renderTemplate baseScriptVars ./guest/agent-command-state.sh;
  renderedProfileLib = renderTemplate baseScriptVars ./guest/profile.sh;
  scriptVars = baseScriptVars // {
    "@ADOPT_HOST_IDENTITY_SCRIPT@" = "${adoptHostIdentityScript}";
    "@FIREBREAK_AGENT_COMMAND_REQUEST_LIB@" = renderedAgentCommandRequestLib;
    "@FIREBREAK_AGENT_COMMAND_STATE_LIB@" = renderedAgentCommandStateLib;
    "@FIREBREAK_PROFILE_LIB@" = renderedProfileLib;
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
  prepareColdAgentExecScript = pkgs.writeShellScript "prepare-cold-agent-exec"
    (renderTemplate scriptVars ./guest/prepare-cold-agent-exec.sh);
  configureRuntimeNetworkScript = pkgs.writeShellScript "configure-runtime-network"
    (renderTemplate scriptVars ./guest/configure-runtime-network.sh);
  guestEgressRelayProgram = pkgs.writeText "firebreak-cloud-hypervisor-egress-relay.py"
    (builtins.readFile ./guest/cloud-hypervisor-egress-relay.py);
  localPublishedHostPorts = builtins.fromJSON cfg.localPublishedHostPortsJson;
  guestPublishedTcpPorts =
    lib.unique
      (map
        (forward: toString ((forward.guest or { }).port))
        (builtins.filter
          (forward:
            ((forward.from or "host") == "host") &&
            ((forward.proto or "tcp") == "tcp") &&
            ((forward.guest or { }) ? port))
          localPublishedHostPorts));
  cloudHypervisorVsockEnabled =
    cfg.runtimeBackend == "cloud-hypervisor" && (
      cfg.guestEgress.enable ||
      guestPublishedTcpPorts != [ ]
    );
  guestPortPublishRelayProgram = pkgs.writeText "firebreak-cloud-hypervisor-port-publish-relay.py"
    (builtins.readFile ./guest/cloud-hypervisor-port-publish-relay.py);
  guestEgressRelayScript = pkgs.writeShellApplication {
    name = "firebreak-cloud-hypervisor-egress-relay";
    runtimeInputs = with pkgs; [ python3 ];
    text = ''
      ${renderedProfileLib}
      firebreak_profile_guest_mark guest-egress-proxy service-start
      export FIREBREAK_GUEST_EGRESS_PROXY_HOST='127.0.0.1'
      export FIREBREAK_GUEST_EGRESS_PROXY_PORT='${toString cfg.guestEgress.proxyPort}'
      export FIREBREAK_GUEST_EGRESS_HOST_CID='2'
      export FIREBREAK_GUEST_EGRESS_HOST_PORT='${toString cfg.guestEgress.proxyPort}'
      firebreak_profile_guest_mark guest-egress-proxy relay-exec
      exec python3 ${guestEgressRelayProgram}
    '';
  };
  guestPortPublishRelayScript = pkgs.writeShellApplication {
    name = "firebreak-cloud-hypervisor-port-publish-relay";
    runtimeInputs = with pkgs; [ python3 ];
    text = ''
      ${renderedProfileLib}
      firebreak_profile_guest_mark guest-port-publish-relay service-start '${lib.concatStringsSep "," guestPublishedTcpPorts}'
      export FIREBREAK_GUEST_PORT_PUBLISH_TARGET_HOST='127.0.0.1'
      export FIREBREAK_GUEST_PORT_PUBLISH_PORTS='${lib.concatStringsSep "," guestPublishedTcpPorts}'
      firebreak_profile_guest_mark guest-port-publish-relay relay-exec
      exec python3 ${guestPortPublishRelayProgram}
    '';
  };
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
  runAgentExecScript = pkgs.writeShellApplication {
    name = "firebreak-run-agent-exec";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      systemd
    ];
    text = renderTemplate scriptVars ./guest/run-agent-exec.sh;
  };
  localCommandAgentScript = pkgs.writeShellScript "firebreak-local-command-agent"
    (renderTemplate (scriptVars // {
      "@RUN_AGENT_EXEC_SCRIPT@" = "${runAgentExecScript}/bin/firebreak-run-agent-exec";
    }) ./guest/local-command-agent.sh);
  devConsoleStartScript = pkgs.writeShellScript "dev-console-start"
    (renderTemplate (scriptVars // {
      "@RUN_AGENT_EXEC_SCRIPT@" = "${runAgentExecScript}/bin/firebreak-run-agent-exec";
    }) ./guest/dev-console-start.sh);
  devConsoleConditionScript = pkgs.writeShellScript "firebreak-dev-console-condition" ''
    set -eu
    session_mode=""
    if [ -r ${lib.escapeShellArg cfg.workerSessionModeFile} ]; then
      session_mode=$(cat ${lib.escapeShellArg cfg.workerSessionModeFile})
    fi
    [ "$session_mode" != "agent-service" ] && [ "$session_mode" != "agent-exec" ]
  '';
  coldCommandExecConditionScript = pkgs.writeShellScript "firebreak-cold-command-exec-condition" ''
    set -eu
    session_mode=""
    if [ -r ${lib.escapeShellArg cfg.workerSessionModeFile} ]; then
      session_mode=$(cat ${lib.escapeShellArg cfg.workerSessionModeFile})
    fi
    [ "$session_mode" = "agent-exec" ]
  '';
  localCommandAgentConditionScript = pkgs.writeShellScript "firebreak-local-command-agent-condition" ''
    set -eu
    session_mode=""
    if [ -r ${lib.escapeShellArg cfg.workerSessionModeFile} ]; then
      session_mode=$(cat ${lib.escapeShellArg cfg.workerSessionModeFile})
    fi
    [ "$session_mode" = "agent-service" ]
  '';
  bootstrapEnabled = cfg.bootstrapScript != null;
in {
  config = lib.mkMerge [
    {
    assertions = [
      {
        assertion =
          if lib.hasSuffix "-darwin" cfg.hostSystem then
            cfg.runtimeBackend == "vfkit"
          else
            cfg.runtimeBackend == "cloud-hypervisor";
        message =
          "firebreak local profile supports only `vfkit` on Darwin and `cloud-hypervisor` on Linux.";
      }
    ];

    workloadVm.requiredCapabilities = [
      "interactive-console"
      "workspace-share"
      "host-meta-share"
    ];
    workloadVm.devHome = lib.mkDefault "/home/${cfg.devUser}";
    workloadVm.varVolumeEnabled = lib.mkDefault false;

    users.users.root.password = "";
    users.users.${cfg.devUser}.password = "";

    networking.useDHCP = lib.mkForce (cfg.runtimeBackend != "cloud-hypervisor");
    networking.firewall.enable = lib.mkForce false;

    security.enableWrappers = lib.mkForce false;
    services.resolved.enable = lib.mkForce false;
    services.timesyncd.enable = lib.mkForce false;
    services.logrotate.enable = lib.mkForce false;

    boot.initrd.systemd.suppressedUnits = [
      "systemd-vconsole-setup.service"
    ];
    boot.kernelModules = lib.mkForce [ ];
    boot.blacklistedKernelModules = [
      "drm"
      "intel_pstate"
      "rfkill"
      "efi_pstore"
      "atkbd"
      "loop"
    ];
    systemd.suppressedSystemUnits = [
      "systemd-journal-catalog-update.service"
    ];
    systemd.services."systemd-update-done".enable = lib.mkForce false;
    systemd.services."systemd-update-utmp".enable = lib.mkForce false;
    systemd.timers."systemd-tmpfiles-clean".enable = lib.mkForce false;
    systemd.services.systemd-vconsole-setup.enable = lib.mkForce false;
    systemd.services.reload-systemd-vconsole-setup.enable = lib.mkForce false;

    workloadVm.hostMetaMount = lib.mkDefault hostMetaMount;
    workloadVm.workerExecOutputMount = lib.mkDefault workerExecOutputMount;
    workloadVm.workerBridgeMount = lib.mkDefault workerBridgeMount;
    workloadVm.guestEgress.enable = lib.mkDefault (builtins.elem "guest-egress" cfg.requiredCapabilities);

    environment.variables = lib.mkIf cfg.guestEgress.enable {
      HTTP_PROXY = "http://127.0.0.1:${toString cfg.guestEgress.proxyPort}";
      HTTPS_PROXY = "http://127.0.0.1:${toString cfg.guestEgress.proxyPort}";
      http_proxy = "http://127.0.0.1:${toString cfg.guestEgress.proxyPort}";
      https_proxy = "http://127.0.0.1:${toString cfg.guestEgress.proxyPort}";
      NO_PROXY = "127.0.0.1,localhost,::1";
      no_proxy = "127.0.0.1,localhost,::1";
    };

    fileSystems.${runtimeHostMount} = {
      device = "hostruntime";
      fsType = hostMetaFsType;
      options = [
        "defaults"
        "x-systemd.after=systemd-modules-load.service"
      ];
    };
    fileSystems.${cfg.toolRuntimesMount} = lib.mkIf (cfg.runtimeBackend == "cloud-hypervisor" && cfg.toolRuntimesEnabled) {
      device = "hostagenttools";
      fsType = "virtiofs";
      options = [
        "defaults"
        "exec"
        "x-systemd.after=systemd-modules-load.service"
      ];
    };
    systemd.services.prepare-agent-session = {
      description = "Prepare the workspace and agent session paths";
      wantedBy = [ "multi-user.target" ];
      before = [ "dev-console.service" ];
      after = [ "local-fs.target" ];

      path = with pkgs; [
        coreutils
        shadow
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

    systemd.services.prepare-cold-agent-exec = {
      description = "Prepare minimal guest state for cold non-interactive command execution";
      wantedBy = [ "firebreak-cold-exec.target" ];
      before = [ "cold-command-exec.service" ];
      after = [ "local-fs.target" ];

      path = with pkgs; [
        coreutils
        util-linux
      ];

      serviceConfig = {
        ExecStart = prepareColdAgentExecScript;
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services.configure-runtime-network = lib.mkIf (cfg.runtimeBackend == "cloud-hypervisor") {
      description = "Configure runtime networking for the local Cloud Hypervisor backend";
      wantedBy = [ "basic.target" ];
      before = [ "dev-console.service" ] ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      after = [ "local-fs.target" ];

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

    systemd.services.guest-egress-proxy = lib.mkIf (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) {
      description = "Expose rootless guest egress through Cloud Hypervisor vsock";
      wantedBy = [ "basic.target" ];
      before = [ "dev-console.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      after = [ "local-fs.target" ];

      serviceConfig = {
        ExecStart = "${guestEgressRelayScript}/bin/firebreak-cloud-hypervisor-egress-relay";
        Restart = "always";
        RestartSec = 1;
        Type = "simple";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services.guest-port-publish-relay = lib.mkIf (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) {
      description = "Expose localhost TCP services through the Cloud Hypervisor vsock mux";
      wantedBy = [ "basic.target" ];
      before = [ "dev-console.service" ]
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      after = [ "local-fs.target" ];

      serviceConfig = {
        ExecStart = "${guestPortPublishRelayScript}/bin/firebreak-cloud-hypervisor-port-publish-relay";
        Restart = "always";
        RestartSec = 1;
        Type = "simple";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.services.cold-command-exec = {
      description = "Cold non-interactive command execution";
      wantedBy = [ "firebreak-cold-exec.target" ];
      after = [ "prepare-cold-agent-exec.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) "guest-port-publish-relay.service";
      requires = [ "prepare-cold-agent-exec.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) "guest-port-publish-relay.service";

      serviceConfig = {
        ExecCondition = coldCommandExecConditionScript;
        ExecStart = "${runAgentExecScript}/bin/firebreak-run-agent-exec";
        Type = "simple";
        WorkingDirectory = devHome;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    systemd.targets.firebreak-cold-exec = {
      description = "Minimal cold command execution target";
      after = [ "basic.target" ];
      wants = [
        "basic.target"
        "cold-command-exec.service"
      ];
    };

    systemd.services.dev-bootstrap = lib.mkIf bootstrapEnabled {
      after = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service";
      requires = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service";
    };

    systemd.services."serial-getty@ttyS0".enable = false;

    environment.systemPackages =
      lib.optionals cfg.workerBridgeEnabled [
        firebreakWorkerBridgeCli
        firebreakWorkerLocalHelper
      ]
      ++ [
        runAgentExecScript
      ];

    systemd.services.dev-console = {
      description = "Interactive dev shell on ttyS0";
      wantedBy = [ "multi-user.target" ];
      after = [ "cold-command-exec.service" "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) "guest-port-publish-relay.service"
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) "guest-port-publish-relay.service"
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      wants = [ ];
      conflicts = [ "serial-getty@ttyS0.service" ];

      serviceConfig = {
        ExecCondition = devConsoleConditionScript;
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

    systemd.services.local-command-agent = {
      description = "Warm local command agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) "guest-port-publish-relay.service"
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";
      requires = [ "prepare-agent-session.service" ]
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor") "configure-runtime-network.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && cfg.guestEgress.enable) "guest-egress-proxy.service"
        ++ lib.optional (cfg.runtimeBackend == "cloud-hypervisor" && guestPublishedTcpPorts != [ ]) "guest-port-publish-relay.service"
        ++ lib.optional bootstrapEnabled "dev-bootstrap.service";

      serviceConfig = {
        ExecCondition = localCommandAgentConditionScript;
        ExecStart = localCommandAgentScript;
        Restart = "always";
        RestartSec = 1;
        Type = "simple";
        User = cfg.devUser;
        WorkingDirectory = devHome;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    microvm.extraArgsScript = lib.optionalString (cfg.runtimeBackend != "vfkit") "${runtimeExtraArgsScript}";
    microvm.shares = lib.mkAfter (
      lib.optionals (cfg.runtimeBackend == "cloud-hypervisor") [
        {
          proto = "virtiofs";
          tag = "hostcwd";
          socket = hostCwdShareSocket;
          source = "/run/firebreak/hostcwd";
          mountPoint = cfg.workspaceMount;
        }
        {
          proto = "virtiofs";
          tag = "hostruntime";
          socket = hostRuntimeShareSocket;
          source = "/run/firebreak/hostruntime";
          mountPoint = runtimeHostMount;
        }
      ]
      ++ lib.optionals (cfg.runtimeBackend == "cloud-hypervisor" && cfg.sharedStateRoots.enable) [
        {
          proto = "virtiofs";
          tag = "hoststateroot";
          socket = sharedStateRootShareSocket;
          source = "/run/firebreak/hoststateroot";
          mountPoint = cfg.sharedStateRoots.hostMount;
        }
      ]
      ++ lib.optionals (cfg.runtimeBackend == "cloud-hypervisor" && cfg.sharedCredentialSlots.enable) [
        {
          proto = "virtiofs";
          tag = "hostcredentialslots";
          socket = sharedCredentialSlotsShareSocket;
          source = "/run/firebreak/hostcredentialslots";
          mountPoint = cfg.sharedCredentialSlots.hostMount;
        }
      ]
      ++ lib.optionals (cfg.runtimeBackend == "cloud-hypervisor" && cfg.toolRuntimesEnabled) [
        {
          proto = "virtiofs";
          tag = "hostagenttools";
          socket = agentToolsShareSocket;
          source = "/run/firebreak/hostagenttools";
          mountPoint = cfg.toolRuntimesMount;
        }
      ]
    );

    microvm.vsock.cid = lib.mkIf cloudHypervisorVsockEnabled (lib.mkDefault cfg.guestEgress.vsockCID);

    workloadVm.runtimeManagedRoStore = cfg.runtimeBackend != "vfkit";
    }

    (lib.mkIf (cfg.runtimeBackend == "cloud-hypervisor") {
      # Keep the local Cloud Hypervisor initrd focused on the devices we
      # actually expose instead of the generic host-hardware autodetect set.
      boot.initrd.availableKernelModules = lib.mkForce [
        "virtio_blk"
        "virtio_mmio"
        "virtio_pci"
        "virtiofs"
      ];

      boot.initrd.kernelModules = lib.mkForce [
        "dm_mod"
        "virtio_blk"
        "virtio_mmio"
        "virtio_pci"
        "virtiofs"
      ];
    })
  ];
}
