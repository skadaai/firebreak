{ self, nixpkgs, microvm, system, guestSystem, renderTemplate, runtimeBackends }:
let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};

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
    controlSocketName,
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
  }:
    let
      runnerWrapper = pkgs.writeShellScript "firebreak-runner-wrapper" ''
        set -eu
        . ${runner}/bin/firebreak-runner-extra-args
        exec ${runner}/bin/microvm-run "$@" "''${firebreak_extra_args[@]}"
      '';
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
          util-linux
        ] ++ lib.optional pkgs.stdenv.hostPlatform.isLinux virtiofsd;
      text = renderTemplate {
        "@HOST_SYSTEM@" = system;
        "@CONTROL_SOCKET@" = "${controlSocketName}.socket";
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
        "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../../modules/base/host/firebreak-project-config.sh;
        "@FIREBREAK_FLAKE_REF@" = "path:${builtins.toString ../../.}";
        "@FIREBREAK_WORKER_LIB@" = builtins.readFile ../../modules/base/host/firebreak-worker.sh;
        "@FIREBREAK_WORKER_BRIDGE_HOST_LIB@" = builtins.readFile ../../modules/profiles/local/host/firebreak-worker-bridge-host.sh;
        "@WORKER_BRIDGE_ENABLED@" = if workerBridgeEnabled then "1" else "0";
      } ../../modules/profiles/local/host/run-wrapper.sh;
    };

  mkLocalVmPackage = {
    name,
    runnerPackage,
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
  }:
    mkWorkloadPackage {
      inherit
        name
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
