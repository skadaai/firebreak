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
            "@CONTROL_SOCKET@" = "${runnerName}.socket";
            "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
            "@DEFAULT_AGENT_SESSION_MODE@" = defaultAgentSessionMode;
            "@RUNNER@" = "${self.packages.${system}."${runnerName}-runner"}/bin/microvm-run";
            "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
          } ./modules/base/host/run-wrapper.sh;
        };

      mkSmokePackage = {
        name,
        agentPackage,
        shellPackage,
        agentBin,
        agentDisplayName,
        agentConfigDirName,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            expect
            git
          ];
          text = renderTemplate {
            "@AGENT_BIN@" = agentBin;
            "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
            "@AGENT_DISPLAY_NAME@" = agentDisplayName;
            "@AGENT_PACKAGE@" = agentPackage;
            "@AGENT_SHELL_PACKAGE@" = shellPackage;
          } ./modules/base/tests/agent-smoke.sh;
        };
    in {
      nixosModules = {
        agent-vm-base = import ./modules/base/module.nix;
        firebreak-codex = import ./modules/codex/module.nix;
        firebreak-claude-code = import ./modules/claude-code/module.nix;
        default = self.nixosModules.firebreak-codex;
      };

      nixosConfigurations = {
        firebreak-codex = mkAgentVm {
          name = "firebreak-codex";
          extraModules = [ self.nixosModules.firebreak-codex ];
        };
        firebreak-claude-code = mkAgentVm {
          name = "firebreak-claude-code";
          extraModules = [ self.nixosModules.firebreak-claude-code ];
        };
      };

      packages.${system} = {
        default = self.packages.${system}.firebreak;
        firebreak-codex-runner = self.nixosConfigurations.firebreak-codex.config.microvm.declaredRunner;
        firebreak-claude-code-runner = self.nixosConfigurations.firebreak-claude-code.config.microvm.declaredRunner;
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
        firebreak-codex-smoke = mkSmokePackage {
          name = "firebreak-codex-smoke";
          agentPackage = "firebreak-codex";
          shellPackage = "firebreak-codex-shell";
          agentBin = "codex";
          agentDisplayName = "Codex";
          agentConfigDirName = ".codex";
        };
        firebreak-claude-code = mkAgentPackage {
          name = "firebreak-claude-code";
          runnerName = "firebreak-claude-code";
          defaultAgentCommand = "claude";
          defaultAgentConfigHostDir = "$HOME/.claude";
          defaultAgentSessionMode = "agent";
        };
        firebreak-claude-code-shell = mkAgentPackage {
          name = "firebreak-claude-code-shell";
          runnerName = "firebreak-claude-code";
          defaultAgentCommand = "claude";
          defaultAgentConfigHostDir = "$HOME/.claude";
          defaultAgentSessionMode = "shell";
        };
        firebreak-claude-code-smoke = mkSmokePackage {
          name = "firebreak-claude-code-smoke";
          agentPackage = "firebreak-claude-code";
          shellPackage = "firebreak-claude-code-shell";
          agentBin = "claude";
          agentDisplayName = "Claude Code";
          agentConfigDirName = ".claude";
        };
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
  nix run github:skadaai/firebreak#firebreak-claude-code
  nix run github:skadaai/firebreak#firebreak-claude-code-shell
  nix run github:skadaai/firebreak#firebreak-claude-code-smoke
EOF
          '';
        };
      };

      checks.${system} = {
        firebreak-codex-runner = self.packages.${system}.firebreak-codex-runner;
        firebreak-codex-system = self.nixosConfigurations.firebreak-codex.config.system.build.toplevel;
        firebreak-codex-smoke = self.packages.${system}.firebreak-codex-smoke;
        firebreak-claude-code-runner = self.packages.${system}.firebreak-claude-code-runner;
        firebreak-claude-code-system = self.nixosConfigurations.firebreak-claude-code.config.system.build.toplevel;
        firebreak-claude-code-smoke = self.packages.${system}.firebreak-claude-code-smoke;
      };
    };
}
