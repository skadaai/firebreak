{
  description = "MicroVM sandboxes for coding agents";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      renderTemplate = vars: path:
        lib.replaceStrings
          (builtins.attrNames vars)
          (builtins.attrValues vars)
          (builtins.readFile path);

      mkAgentVm = {
        name,
        extraModules ? [ ],
      }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit renderTemplate;
          };
          modules = [
            microvm.nixosModules.microvm
            self.nixosModules.agent-vm-base
            {
              agentVm.name = name;
            }
          ] ++ extraModules;
        };

      mkAgentPackage = {
        name,
        runnerName,
        defaultAgentConfigHostDir,
        defaultAgentSessionMode,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils virtiofsd ];
          text = renderTemplate {
            "@DEFAULT_AGENT_SESSION_MODE@" = defaultAgentSessionMode;
            "@RUNNER@" = "${self.packages.${system}."${runnerName}-runner"}/bin/microvm-run";
            "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
          } ./scripts/run-wrapper.sh;
        };

      mkSmokePackage = name:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            expect
            git
          ];
          text = builtins.readFile ./tests/codex-vm-smoke.sh;
        };
    in {
      nixosModules = {
        agent-vm-base = import ./nix/modules/agent-vm-base.nix;
        codex-vm = import ./nix/modules/agents/codex.nix;
        default = self.nixosModules.codex-vm;
      };

      nixosConfigurations = {
        codex-vm = mkAgentVm {
          name = "codex-vm";
          extraModules = [ self.nixosModules.codex-vm ];
        };
      };

      packages.${system} = {
        default = self.packages.${system}.codex-vm;
        codex-vm-runner = self.nixosConfigurations.codex-vm.config.microvm.declaredRunner;
        codex-vm = mkAgentPackage {
          name = "codex-vm";
          runnerName = "codex-vm";
          defaultAgentConfigHostDir = "$HOME/.codex";
          defaultAgentSessionMode = "agent";
        };
        codex-vm-shell = mkAgentPackage {
          name = "codex-vm-shell";
          runnerName = "codex-vm";
          defaultAgentConfigHostDir = "$HOME/.codex";
          defaultAgentSessionMode = "shell";
        };
        codex-vm-smoke = mkSmokePackage "codex-vm-smoke";
      };

      checks.${system} = {
        codex-vm-runner = self.packages.${system}.codex-vm-runner;
        codex-vm-system = self.nixosConfigurations.codex-vm.config.system.build.toplevel;
        codex-vm-smoke = self.packages.${system}.codex-vm-smoke;
      };
    };
}
