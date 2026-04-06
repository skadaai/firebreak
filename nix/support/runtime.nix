{ self, nixpkgs, microvm, system, guestSystem, renderTemplate, runtimeBackends, nixpkgsConfig }:
let
  lib = nixpkgs.lib;
  pkgs = import nixpkgs {
    inherit system;
    config = nixpkgsConfig;
  };

  mkRunnerPackage = runner:
    pkgs.runCommand "${runner.name}-compat" {
      nativeBuildInputs = with pkgs; [
        coreutils
        gnugrep
        gnused
      ];
    } ''
      mkdir -p "$out"
      for entry in ${runner}/*; do
        name=$(basename "$entry")
        ln -s "$entry" "$out/$name"
      done
      rm -f "$out/bin"
      mkdir -p "$out/bin"
      for entry in ${runner}/bin/*; do
        name=$(basename "$entry")
        if [ "$name" = "microvm-run" ]; then
          cp --no-preserve=mode,ownership "$entry" "$out/bin/$name"
          chmod u+w+x "$out/bin/$name"
        else
          ln -s "$entry" "$out/bin/$name"
        fi
      done
      if grep -F -q 'aio=io_uring' "$out/bin/microvm-run"; then
        substituteInPlace "$out/bin/microvm-run" \
          --replace-fail 'aio=io_uring' 'aio=threads'
      fi
      if [ "${system}" = "x86_64-linux" ] && grep -F -q -- '-enable-kvm -cpu host,+x2apic,-sgx' "$out/bin/microvm-run"; then
        substituteInPlace "$out/bin/microvm-run" \
          --replace-fail '-enable-kvm -cpu host,+x2apic,-sgx' '$(if [ -r /dev/kvm ]; then printf "%s" "-enable-kvm -cpu host,+x2apic,-sgx"; else printf "%s" "-cpu max"; fi)'
      fi

      cat > "$out/bin/firebreak-runner-extra-args" <<'EOF'
firebreak_extra_args=()

if [ -n "''${MICROVM_VFKIT_HOST_CWD_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_HOST_CWD_DIR},mountTag=hostcwd")
fi

if [ -n "''${MICROVM_VFKIT_HOST_META_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_HOST_META_DIR},mountTag=hostmeta")
fi

if [ -n "''${MICROVM_VFKIT_SHARED_STATE_ROOT_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_SHARED_STATE_ROOT_DIR},mountTag=hoststateroot")
fi

if [ -n "''${MICROVM_VFKIT_SHARED_CREDENTIAL_SLOTS_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_SHARED_CREDENTIAL_SLOTS_DIR},mountTag=hostcredentialslots")
fi

if [ -n "''${MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR},mountTag=hostexecoutput")
fi

if [ -n "''${MICROVM_VFKIT_AGENT_TOOLS_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_AGENT_TOOLS_DIR},mountTag=hostagenttools")
fi

if [ -n "''${MICROVM_VFKIT_WORKER_BRIDGE_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_WORKER_BRIDGE_DIR},mountTag=hostworkerbridge")
fi
EOF
      chmod 0555 "$out/bin/firebreak-runner-extra-args"
    '';

  mkWorkloadVm = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
    runtimeBackend ? null,
  }:
    nixpkgs.lib.nixosSystem {
      system = guestSystem;
      specialArgs = {
        inherit renderTemplate runtimeBackends;
      };
      modules = [
        microvm.nixosModules.microvm
        self.nixosModules.firebreak-vm-base
        {
          nixpkgs.config = nixpkgsConfig;
        }
        {
          workloadVm.name = name;
          workloadVm.hostSystem = system;
          workloadVm.guestSystem = guestSystem;
          workloadVm.runtimeBackend = lib.mkDefault (
            if runtimeBackend != null then
              runtimeBackend
            else
              runtimeBackends.defaultLocalBackendForHost system
          );
          microvm.vmHostPackages = pkgs;
        }
      ] ++ profileModules ++ extraModules;
    };

  mkWorkloadPackage = {
    name,
    runner,
    runtimeBackend,
    controlSocketName,
    networkMac,
    defaultAgentCommand ? "",
    agentConfigSubdir ? "agent",
    defaultAgentConfigHostDir,
    defaultCredentialSlotsHostDir ? "$HOME/.firebreak/credentials",
    workspaceBootstrapConfigHostDir ? "",
    hostConfigAdoptionEnabled ? false,
    agentEnvPrefix ? "AGENT",
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    workerBridgeEnabled ? false,
    localPublishedHostPortsJson ? "[]",
    guestEgressEnabled ? false,
    guestEgressProxyPort ? 3128,
  }:
    let
      runnerWrapper = pkgs.writeShellScript "firebreak-runner-wrapper" ''
        set -eu
        . ${runner}/bin/firebreak-runner-extra-args
        exec ${runner}/bin/microvm-run "$@" "''${firebreak_extra_args[@]}"
      '';
      wrapperTemplateVars = {
        "@HOST_SYSTEM@" = system;
        "@RUNTIME_BACKEND@" = runtimeBackend;
        "@CONTROL_SOCKET@" = "${controlSocketName}.socket";
        "@NETWORK_MAC@" = networkMac;
        "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
        "@RUNNER@" = "${runnerWrapper}";
        "@STATE_SUBDIR@" = agentConfigSubdir;
        "@DEFAULT_STATE_ROOT@" = defaultAgentConfigHostDir;
        "@DEFAULT_CREDENTIAL_SLOTS_HOST_DIR@" = defaultCredentialSlotsHostDir;
        "@WORKSPACE_BOOTSTRAP_CONFIG_HOST_DIR@" = workspaceBootstrapConfigHostDir;
        "@HOST_CONFIG_ADOPTION_ENABLED@" = if hostConfigAdoptionEnabled then "1" else "0";
        "@AGENT_ENV_PREFIX@" = agentEnvPrefix;
        "@SHARED_STATE_ROOT_ENABLED@" = if (sharedStateRoots.enable or false) then "1" else "0";
        "@SHARED_CREDENTIAL_SLOTS_ENABLED@" = if (sharedCredentialSlots.enable or false) then "1" else "0";
        "@LOCAL_PUBLISHED_HOST_PORTS_JSON@" = localPublishedHostPortsJson;
        "@GUEST_EGRESS_ENABLED@" = if guestEgressEnabled then "1" else "0";
        "@GUEST_EGRESS_PROXY_PORT@" = toString guestEgressProxyPort;
        "@FIREBREAK_FLAKE_REF@" = "path:${builtins.toString ../../.}";
        "@WORKER_BRIDGE_ENABLED@" = if workerBridgeEnabled then "1" else "0";
      };
      renderedCloudHypervisorNetworkLib = renderTemplate
        (wrapperTemplateVars // {
          "@FIREBREAK_CLOUD_HYPERVISOR_PORT_PUBLISH_PROXY_PY@" = builtins.readFile ../../modules/profiles/local/host/cloud-hypervisor-port-publish.py;
        })
        ../../modules/profiles/local/host/cloud-hypervisor-network.sh;
      renderedCloudHypervisorVsockLib = renderTemplate
        (wrapperTemplateVars // {
          "@FIREBREAK_CLOUD_HYPERVISOR_EGRESS_PROXY_PY@" = builtins.readFile ../../modules/profiles/local/host/cloud-hypervisor-egress-proxy.py;
        })
        ../../modules/profiles/local/host/cloud-hypervisor-vsock.sh;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs =
        with pkgs;
        [
          bash
          coreutils
          git
          gnused
          nix
          python3
          sudo
          util-linux
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          iproute2
          iptables
          socat
          virtiofsd
        ];
      text = renderTemplate (wrapperTemplateVars // {
        "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../../modules/base/host/firebreak-project-config.sh;
        "@FIREBREAK_WORKER_LIB@" = builtins.readFile ../../modules/base/host/firebreak-worker.sh;
        "@FIREBREAK_WORKER_BRIDGE_HOST_LIB@" = builtins.readFile ../../modules/profiles/local/host/firebreak-worker-bridge-host.sh;
        "@FIREBREAK_CLOUD_HYPERVISOR_NETWORK_LIB@" = renderedCloudHypervisorNetworkLib;
        "@FIREBREAK_CLOUD_HYPERVISOR_VSOCK_LIB@" = renderedCloudHypervisorVsockLib;
        "@FIREBREAK_LOCAL_COMMAND_REQUEST_LIB@" = builtins.readFile ../../modules/profiles/local/host/command-request.sh;
        "@FIREBREAK_LOCAL_INSTANCE_CONTROLLER_LIB@" = builtins.readFile ../../modules/profiles/local/host/local-instance-controller.sh;
        "@FIREBREAK_PROFILE_SUMMARY_SCRIPT@" = builtins.toString ../../modules/profiles/local/host/profile-summary.py;
        "@PYTHON3@" = "${pkgs.python3}/bin/python3";
      }) ../../modules/profiles/local/host/run-wrapper.sh;
    };

  mkLocalVmPackage = {
    name,
    runnerPackage,
    runtimeBackend,
    controlSocketName ? name,
    networkMac,
    defaultAgentCommand ? "",
    agentConfigSubdir ? "agent",
    defaultAgentConfigHostDir ? "$HOME/.firebreak",
    defaultCredentialSlotsHostDir ? "$HOME/.firebreak/credentials",
    workspaceBootstrapConfigHostDir ? "",
    hostConfigAdoptionEnabled ? false,
    agentEnvPrefix ? "AGENT",
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    workerBridgeEnabled ? false,
    localPublishedHostPortsJson ? "[]",
    guestEgressEnabled ? false,
    guestEgressProxyPort ? 3128,
  }:
    mkWorkloadPackage {
      inherit
        name
        runtimeBackend
        controlSocketName
        networkMac
        defaultAgentCommand
        agentConfigSubdir
        defaultAgentConfigHostDir
        defaultCredentialSlotsHostDir
        workspaceBootstrapConfigHostDir
        hostConfigAdoptionEnabled
        agentEnvPrefix
        sharedStateRoots
        sharedCredentialSlots
        workerBridgeEnabled
        localPublishedHostPortsJson
        guestEgressEnabled
        guestEgressProxyPort;
      runner = runnerPackage;
    };

  mkLocalVmArtifacts = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
    runtimeBackend ? null,
    controlSocketName ? name,
    defaultAgentCommand ? "",
    agentConfigSubdir ? "agent",
    defaultAgentConfigHostDir ? "$HOME/.firebreak",
    defaultCredentialSlotsHostDir ? "$HOME/.firebreak/credentials",
    workspaceBootstrapConfigHostDir ? "",
    hostConfigAdoptionEnabled ? false,
    agentEnvPrefix ? "AGENT",
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    workerBridgeEnabled ? false,
    workerKinds ? { },
  }:
    let
      nixosConfiguration = mkWorkloadVm {
        inherit name profileModules runtimeBackend;
        extraModules =
          extraModules
          ++ nixpkgs.lib.optional (workerKinds != { }) {
            workloadVm.workerKindsJson = builtins.toJSON workerKinds;
          }
          ++ nixpkgs.lib.optional workerBridgeEnabled {
            workloadVm.workerBridgeEnabled = true;
          };
      };
      runnerPackage = mkRunnerPackage nixosConfiguration.config.microvm.declaredRunner;
      package = mkLocalVmPackage {
        inherit
          name
          runnerPackage
          controlSocketName
          defaultAgentCommand
          agentConfigSubdir
          defaultAgentConfigHostDir
          defaultCredentialSlotsHostDir
          workspaceBootstrapConfigHostDir
          hostConfigAdoptionEnabled
          agentEnvPrefix
          sharedStateRoots
          sharedCredentialSlots
          workerBridgeEnabled;
        runtimeBackend = nixosConfiguration.config.workloadVm.runtimeBackend;
        networkMac = nixosConfiguration.config.workloadVm.macAddress;
        localPublishedHostPortsJson = nixosConfiguration.config.workloadVm.localPublishedHostPortsJson;
        guestEgressEnabled = nixosConfiguration.config.workloadVm.guestEgress.enable;
        guestEgressProxyPort = nixosConfiguration.config.workloadVm.guestEgress.proxyPort;
      };
    in {
      inherit nixosConfiguration package runnerPackage;
  };
in {
  inherit
    mkWorkloadPackage
    mkWorkloadVm
    mkLocalVmArtifacts
    mkLocalVmPackage
    mkRunnerPackage
    runtimeBackends
    ;
}
