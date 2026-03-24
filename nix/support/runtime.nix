{ self, nixpkgs, microvm, system, renderTemplate }:
let
  pkgs = nixpkgs.legacyPackages.${system};

  mkRunnerPackage = runner:
    pkgs.runCommand "${runner.name}-compat" {
      nativeBuildInputs = with pkgs; [
        coreutils
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
      substituteInPlace "$out/bin/microvm-run" \
        --replace-fail 'aio=io_uring' 'aio=threads' \
        --replace-fail '-enable-kvm -cpu host,+x2apic,-sgx' '$(if [ -r /dev/kvm ]; then printf "%s" "-enable-kvm -cpu host,+x2apic,-sgx"; else printf "%s" "-cpu max"; fi)'
    '';

  mkAgentVm = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
  }:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit renderTemplate;
      };
      modules = [
        microvm.nixosModules.microvm
        self.nixosModules.firebreak-vm-base
        {
          agentVm.name = name;
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
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ coreutils git virtiofsd ];
      text = renderTemplate {
        "@CONTROL_SOCKET@" = "${controlSocketName}.socket";
        "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
        "@RUNNER@" = "${runner}/bin/microvm-run";
        "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
        "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
        "@AGENT_ENV_PREFIX@" = agentEnvPrefix;
        "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../../modules/base/host/firebreak-project-config.sh;
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
  }:
    mkAgentPackage {
      inherit
        name
        controlSocketName
        defaultAgentCommand
        agentConfigDirName
        defaultAgentConfigHostDir
        agentEnvPrefix;
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
  }:
    let
      nixosConfiguration = mkAgentVm {
        inherit name extraModules profileModules;
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
          agentEnvPrefix;
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
