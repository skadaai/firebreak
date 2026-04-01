{ self, nixpkgs, microvm, system, guestSystem, renderTemplate }:
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

if [ -n "''${MICROVM_VFKIT_AGENT_CONFIG_HOST_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_AGENT_CONFIG_HOST_DIR},mountTag=hostagentconfig")
fi

if [ -n "''${MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR},mountTag=hostexecoutput")
fi
EOF
      chmod 0555 "$out/bin/firebreak-runner-extra-args"
    '';

  mkAgentVm = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
  }:
    nixpkgs.lib.nixosSystem {
      system = guestSystem;
      specialArgs = {
        inherit renderTemplate;
      };
      modules = [
        microvm.nixosModules.microvm
        self.nixosModules.firebreak-vm-base
        {
          agentVm.name = name;
          agentVm.hostSystem = system;
          agentVm.guestSystem = guestSystem;
          microvm.vmHostPackages = pkgs;
        }
      ] ++ profileModules ++ extraModules;
    };

  mkAgentPackage = {
    name,
    runner,
    controlSocketName,
    defaultAgentCommand ? "",
    agentConfigDirName,
    defaultAgentConfigHostDir,
    agentEnvPrefix ? "AGENT",
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
        "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
        "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
        "@AGENT_ENV_PREFIX@" = agentEnvPrefix;
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
    agentConfigDirName ? ".firebreak",
    defaultAgentConfigHostDir ? "$HOME/.firebreak/${name}",
    agentEnvPrefix ? "AGENT",
    workerBridgeEnabled ? false,
  }:
    mkAgentPackage {
      inherit
        name
        controlSocketName
        defaultAgentCommand
        agentConfigDirName
        defaultAgentConfigHostDir
        agentEnvPrefix
        workerBridgeEnabled;
      runner = runnerPackage;
    };

  mkLocalVmArtifacts = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
    controlSocketName ? name,
    defaultAgentCommand ? "",
    agentConfigDirName ? ".firebreak",
    defaultAgentConfigHostDir ? "$HOME/.firebreak/${name}",
    agentEnvPrefix ? "AGENT",
    workerBridgeEnabled ? false,
    workerKinds ? { },
  }:
    let
      nixosConfiguration = mkAgentVm {
        inherit name profileModules;
        extraModules =
          extraModules
          ++ nixpkgs.lib.optional (workerKinds != { }) {
            agentVm.workerKindsJson = builtins.toJSON workerKinds;
          }
          ++ nixpkgs.lib.optional workerBridgeEnabled {
            agentVm.workerBridgeEnabled = true;
          };
      };
      runnerPackage = mkRunnerPackage nixosConfiguration.config.microvm.declaredRunner;
      package = mkLocalVmPackage {
        inherit
          name
          runnerPackage
          controlSocketName
          defaultAgentCommand
          agentConfigDirName
          defaultAgentConfigHostDir
          agentEnvPrefix
          workerBridgeEnabled;
      };
    in {
      inherit nixosConfiguration package runnerPackage;
    };
in {
  inherit
    mkAgentPackage
    mkAgentVm
    mkLocalVmArtifacts
    mkLocalVmPackage
    mkRunnerPackage
    ;
}
