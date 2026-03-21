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
        runnerName,
        defaultAgentCommand,
        agentConfigDirName,
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
            "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
            "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
          } ./modules/profiles/local/host/run-wrapper.sh;
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
            bash
            coreutils
            expect
            git
            gnutar
          ];
          text = renderTemplate {
            "@AGENT_BIN@" = agentBin;
            "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
            "@AGENT_DISPLAY_NAME@" = agentDisplayName;
            "@AGENT_PACKAGE@" = agentPackage;
            "@AGENT_SHELL_PACKAGE@" = shellPackage;
          } ./modules/base/tests/agent-smoke.sh;
        };

      mkCloudJobPackage = {
        name,
        runnerName,
        defaultStateDir,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            findutils
            gnugrep
            gnused
            util-linux
            virtiofsd
          ];
          text = renderTemplate {
            "@DEFAULT_STATE_DIR@" = defaultStateDir;
            "@RUNNER@" = "${self.packages.${system}."${runnerName}-runner"}/bin/microvm-run";
          } ./modules/profiles/cloud/host/run-job.sh;
        };

      mkCloudSmokePackage = {
        name,
        jobPackage,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils ];
          text = renderTemplate {
            "@JOB_PACKAGE_BIN@" = "${self.packages.${system}.${jobPackage}}/bin/${jobPackage}";
          } ./modules/profiles/cloud/tests/cloud-smoke.sh;
        };

      mkValidationPackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            gnused
          ];
          text = renderTemplate {
            "@CODEX_SMOKE_BIN@" = "${self.packages.${system}.firebreak-codex-smoke}/bin/firebreak-codex-smoke";
            "@CODEX_VERSION_BIN@" = "${self.packages.${system}.firebreak-codex-version-smoke}/bin/firebreak-codex-version-smoke";
            "@CLAUDE_SMOKE_BIN@" = "${self.packages.${system}.firebreak-claude-code-smoke}/bin/firebreak-claude-code-smoke";
            "@CLOUD_SMOKE_BIN@" = "${self.packages.${system}.firebreak-cloud-job-smoke}/bin/firebreak-cloud-job-smoke";
          } ./modules/base/host/firebreak-validate.sh;
        };

      mkAgentVersionSmokePackage = {
        name,
        agentPackage,
        agentDisplayName,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils ];
          text = renderTemplate {
            "@AGENT_PACKAGE_BIN@" = "${self.packages.${system}.${agentPackage}}/bin/${agentPackage}";
            "@AGENT_DISPLAY_NAME@" = agentDisplayName;
          } ./modules/base/tests/agent-version-smoke.sh;
        };

      mkValidationSmokePackage = { name, validatePackage }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            gnused
          ];
          text = renderTemplate {
            "@VALIDATE_BIN@" = "${self.packages.${system}.${validatePackage}}/bin/${validatePackage}";
          } ./modules/base/tests/validation-smoke.sh;
        };

      mkSessionPackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            bash
            coreutils
            git
            gnused
          ];
          text = builtins.readFile ./modules/base/host/firebreak-session.sh;
        };

      mkSessionSmokePackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            bash
            coreutils
            findutils
            git
            gnugrep
            gnused
          ];
          text = builtins.readFile ./modules/base/tests/session-smoke.sh;
        };

      mkAutonomyPackage = { name, sessionPackage }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            git
            gnugrep
            gnused
          ];
          text = renderTemplate {
            "@SESSION_BIN@" = "${self.packages.${system}.${sessionPackage}}/bin/${sessionPackage}";
          } ./modules/base/host/firebreak-autonomy.sh;
        };

      mkAutonomySmokePackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            bash
            coreutils
            git
            gnugrep
            gnused
          ];
          text = builtins.readFile ./modules/base/tests/autonomy-smoke.sh;
        };

      mkFirebreakCliPackage = { name, validatePackage, sessionPackage, autonomyPackage }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils ];
          text = renderTemplate {
            "@VALIDATE_BIN@" = "${self.packages.${system}.${validatePackage}}/bin/${validatePackage}";
            "@SESSION_BIN@" = "${self.packages.${system}.${sessionPackage}}/bin/${sessionPackage}";
            "@AUTONOMY_BIN@" = "${self.packages.${system}.${autonomyPackage}}/bin/${autonomyPackage}";
          } ./modules/base/host/firebreak.sh;
        };
    in {
      nixosModules = {
        firebreak-vm-base = import ./modules/base/module.nix;
        firebreak-local-profile = import ./modules/profiles/local/module.nix;
        firebreak-cloud-profile = import ./modules/profiles/cloud/module.nix;
        agent-vm-base = {
          imports = [
            self.nixosModules.firebreak-vm-base
            self.nixosModules.firebreak-local-profile
          ];
        };
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
        firebreak-codex-cloud = mkAgentVm {
          name = "firebreak-codex-cloud";
          profileModules = [ self.nixosModules.firebreak-cloud-profile ];
          extraModules = [ self.nixosModules.firebreak-codex ];
        };
        firebreak-claude-code-cloud = mkAgentVm {
          name = "firebreak-claude-code-cloud";
          profileModules = [ self.nixosModules.firebreak-cloud-profile ];
          extraModules = [ self.nixosModules.firebreak-claude-code ];
        };
        firebreak-cloud-smoke = mkAgentVm {
          name = "firebreak-cloud-smoke";
          profileModules = [ self.nixosModules.firebreak-cloud-profile ];
          extraModules = [ {
            agentVm = {
              agentConfigEnabled = false;
              agentPromptCommand = ''
                case "$FIREBREAK_AGENT_PROMPT" in
                  "Run the timeout validation fixture")
                    ./timeout-fixture.sh
                    ;;
                  *)
                    printf '%s\n' "$FIREBREAK_AGENT_PROMPT"
                    ;;
                esac
              '';
              extraSystemPackages = with pkgs; [ coreutils ];
            };
          } ];
        };
      };

      packages.${system} = {
        default = self.packages.${system}.firebreak;
        firebreak-codex-runner = mkRunnerPackage self.nixosConfigurations.firebreak-codex.config.microvm.declaredRunner;
        firebreak-claude-code-runner = mkRunnerPackage self.nixosConfigurations.firebreak-claude-code.config.microvm.declaredRunner;
        firebreak-codex-cloud-runner = mkRunnerPackage self.nixosConfigurations.firebreak-codex-cloud.config.microvm.declaredRunner;
        firebreak-claude-code-cloud-runner = mkRunnerPackage self.nixosConfigurations.firebreak-claude-code-cloud.config.microvm.declaredRunner;
        firebreak-cloud-smoke-runner = mkRunnerPackage self.nixosConfigurations.firebreak-cloud-smoke.config.microvm.declaredRunner;
        firebreak-codex = mkAgentPackage {
          name = "firebreak-codex";
          runnerName = "firebreak-codex";
          defaultAgentCommand = "codex";
          agentConfigDirName = ".codex";
          defaultAgentConfigHostDir = "$HOME/.codex";
          defaultAgentSessionMode = "agent";
        };
        firebreak-codex-shell = mkAgentPackage {
          name = "firebreak-codex-shell";
          runnerName = "firebreak-codex";
          defaultAgentCommand = "codex";
          agentConfigDirName = ".codex";
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
        firebreak-codex-version-smoke = mkAgentVersionSmokePackage {
          name = "firebreak-codex-version-smoke";
          agentPackage = "firebreak-codex";
          agentDisplayName = "Codex";
        };
        firebreak-claude-code = mkAgentPackage {
          name = "firebreak-claude-code";
          runnerName = "firebreak-claude-code";
          defaultAgentCommand = "claude";
          agentConfigDirName = ".claude";
          defaultAgentConfigHostDir = "$HOME/.claude";
          defaultAgentSessionMode = "agent";
        };
        firebreak-claude-code-shell = mkAgentPackage {
          name = "firebreak-claude-code-shell";
          runnerName = "firebreak-claude-code";
          defaultAgentCommand = "claude";
          agentConfigDirName = ".claude";
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
        firebreak-codex-cloud-job = mkCloudJobPackage {
          name = "firebreak-codex-cloud-job";
          runnerName = "firebreak-codex-cloud";
          defaultStateDir = "$HOME/.firebreak/firebreak-codex-cloud";
        };
        firebreak-claude-code-cloud-job = mkCloudJobPackage {
          name = "firebreak-claude-code-cloud-job";
          runnerName = "firebreak-claude-code-cloud";
          defaultStateDir = "$HOME/.firebreak/firebreak-claude-code-cloud";
        };
        firebreak-cloud-smoke-job = mkCloudJobPackage {
          name = "firebreak-cloud-smoke-job";
          runnerName = "firebreak-cloud-smoke";
          defaultStateDir = "$HOME/.firebreak/firebreak-cloud-smoke";
        };
        firebreak-cloud-job-smoke = mkCloudSmokePackage {
          name = "firebreak-cloud-job-smoke";
          jobPackage = "firebreak-cloud-smoke-job";
        };
        firebreak-validate = mkValidationPackage {
          name = "firebreak-validate";
        };
        firebreak-validation-smoke = mkValidationSmokePackage {
          name = "firebreak-validation-smoke";
          validatePackage = "firebreak-validate";
        };
        firebreak-session = mkSessionPackage {
          name = "firebreak-session";
        };
        firebreak-session-smoke = mkSessionSmokePackage {
          name = "firebreak-session-smoke";
        };
        firebreak-autonomy = mkAutonomyPackage {
          name = "firebreak-autonomy";
          sessionPackage = "firebreak-session";
        };
        firebreak-autonomy-smoke = mkAutonomySmokePackage {
          name = "firebreak-autonomy-smoke";
        };
        firebreak = mkFirebreakCliPackage {
          name = "firebreak";
          validatePackage = "firebreak-validate";
          sessionPackage = "firebreak-session";
          autonomyPackage = "firebreak-autonomy";
        };
      };

      checks.${system} = {
        firebreak-codex-runner = self.packages.${system}.firebreak-codex-runner;
        firebreak-codex-system = self.nixosConfigurations.firebreak-codex.config.system.build.toplevel;
        firebreak-codex-smoke = self.packages.${system}.firebreak-codex-smoke;
        firebreak-codex-cloud-runner = self.packages.${system}.firebreak-codex-cloud-runner;
        firebreak-codex-cloud-system = self.nixosConfigurations.firebreak-codex-cloud.config.system.build.toplevel;
        firebreak-cloud-job-smoke = self.packages.${system}.firebreak-cloud-job-smoke;
        firebreak-autonomy-smoke = self.packages.${system}.firebreak-autonomy-smoke;
        firebreak-session-smoke = self.packages.${system}.firebreak-session-smoke;
        firebreak-validation-smoke = self.packages.${system}.firebreak-validation-smoke;
        firebreak-claude-code-runner = self.packages.${system}.firebreak-claude-code-runner;
        firebreak-claude-code-system = self.nixosConfigurations.firebreak-claude-code.config.system.build.toplevel;
        firebreak-claude-code-smoke = self.packages.${system}.firebreak-claude-code-smoke;
        firebreak-claude-code-cloud-runner = self.packages.${system}.firebreak-claude-code-cloud-runner;
        firebreak-claude-code-cloud-system = self.nixosConfigurations.firebreak-claude-code-cloud.config.system.build.toplevel;
        firebreak-cloud-smoke-runner = self.packages.${system}.firebreak-cloud-smoke-runner;
        firebreak-cloud-smoke-system = self.nixosConfigurations.firebreak-cloud-smoke.config.system.build.toplevel;
      };
    };
}
