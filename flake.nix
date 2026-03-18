{
  description = "Skada Firebreak: reliable isolation for high-trust automation";

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
        defaultAgentCommand,
        defaultAgentConfigHostDir,
        defaultAgentSessionMode,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils virtiofsd ];
          text = renderTemplate {
            "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
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
          text = builtins.readFile ./tests/firebreak-codex-smoke.sh;
        };
    in {
      nixosModules = {
        agent-vm-base = import ./nix/modules/agent-vm-base.nix;
        firebreak-codex = import ./nix/modules/agents/codex.nix;
        default = self.nixosModules.firebreak-codex;
      };

      nixosConfigurations = {
        firebreak-codex = mkAgentVm {
          name = "firebreak-codex";
          extraModules = [ self.nixosModules.firebreak-codex ];
        };
      };

      packages.${system} = {
        default = self.packages.${system}.firebreak;
        firebreak-codex-runner = self.nixosConfigurations.firebreak-codex.config.microvm.declaredRunner;
        firebreak-codex = mkAgentPackage {
          name = "firebreak-codex";
          runnerName = "firebreak-codex";
          defaultAgentCommand = "codex";
          defaultAgentConfigHostDir = "$HOME/.codex";
          defaultAgentSessionMode = "agent";
        };
        firebreak-codex-shell = mkAgentPackage {
          name = "firebreak-codex-shell";
          runnerName = "firebreak-codex";
          defaultAgentCommand = "codex";
          defaultAgentConfigHostDir = "$HOME/.codex";
          defaultAgentSessionMode = "shell";
        };
        firebreak-codex-smoke = mkSmokePackage "firebreak-codex-smoke";
        firebreak = pkgs.writeShellApplication {
          name = "firebreak";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            cat <<'EOF'

[Skada Firebreak -reliable isolation for high-trust automation]


This top-level CLI is reserved for a future control plane.
Use an explicit agent VM for now:
  nix run github:skadaai/firebreak#firebreak-codex
  nix run github:skadaai/firebreak#firebreak-codex-shell
  nix run github:skadaai/firebreak#firebreak-codex-smoke
EOF
          '';
        };
      };

      checks.${system} = {
        firebreak-codex-runner = self.packages.${system}.firebreak-codex-runner;
        firebreak-codex-system = self.nixosConfigurations.firebreak-codex.config.system.build.toplevel;
        firebreak-codex-smoke = self.packages.${system}.firebreak-codex-smoke;
      };
    };
}
