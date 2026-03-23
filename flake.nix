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
        runnerPackage,
        controlSocketName,
        defaultAgentCommand,
        agentConfigDirName,
        defaultAgentConfigHostDir,
      }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils virtiofsd ];
          text = renderTemplate {
            "@CONTROL_SOCKET@" = "${controlSocketName}.socket";
            "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
            "@RUNNER@" = "${self.packages.${system}.${runnerPackage}}/bin/microvm-run";
            "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
            "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
          } ./modules/profiles/local/host/run-wrapper.sh;
        };

      mkSmokePackage = {
        name,
        agentPackage,
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
            "@RUNNER@" = "${self.packages.${system}.${runnerName}}/bin/microvm-run";
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
          } ./modules/profiles/cloud/tests/test-smoke-cloud-job.sh;
        };

      mkValidationPackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            gnused
          ];
          text = renderTemplate {
            "@CODEX_SMOKE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-codex}/bin/firebreak-test-smoke-codex";
            "@CODEX_VERSION_BIN@" = "${self.packages.${system}.firebreak-test-smoke-codex-version}/bin/firebreak-test-smoke-codex-version";
            "@CLAUDE_SMOKE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-claude-code}/bin/firebreak-test-smoke-claude-code";
            "@CLOUD_SMOKE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-cloud-job}/bin/firebreak-test-smoke-cloud-job";
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
          } ./modules/base/tests/test-smoke-internal-validate.sh;
        };

      mkTaskPackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            bash
            coreutils
            git
            gnused
          ];
          text = builtins.readFile ./modules/base/host/firebreak-task.sh;
        };

      mkTaskSmokePackage = { name }:
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
          text = builtins.readFile ./modules/base/tests/test-smoke-internal-task.sh;
        };

      mkLoopPackage = { name, taskPackage }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            coreutils
            git
            gnugrep
            gnused
          ];
          text = renderTemplate {
            "@TASK_BIN@" = "${self.packages.${system}.${taskPackage}}/bin/${taskPackage}";
          } ./modules/base/host/firebreak-loop.sh;
        };

      mkLoopSmokePackage = { name }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [
            bash
            coreutils
            git
            gnugrep
            gnused
          ];
          text = builtins.readFile ./modules/base/tests/test-smoke-internal-loop.sh;
        };

      mkFirebreakCliPackage = { name, validatePackage, taskPackage, loopPackage }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [ coreutils ];
          text = renderTemplate {
            "@VALIDATE_BIN@" = "${self.packages.${system}.${validatePackage}}/bin/${validatePackage}";
            "@TASK_BIN@" = "${self.packages.${system}.${taskPackage}}/bin/${taskPackage}";
            "@LOOP_BIN@" = "${self.packages.${system}.${loopPackage}}/bin/${loopPackage}";
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
        firebreak-internal-runner-codex = mkRunnerPackage self.nixosConfigurations.firebreak-codex.config.microvm.declaredRunner;
        firebreak-internal-runner-claude-code = mkRunnerPackage self.nixosConfigurations.firebreak-claude-code.config.microvm.declaredRunner;
        firebreak-internal-runner-codex-cloud = mkRunnerPackage self.nixosConfigurations.firebreak-codex-cloud.config.microvm.declaredRunner;
        firebreak-internal-runner-claude-code-cloud = mkRunnerPackage self.nixosConfigurations.firebreak-claude-code-cloud.config.microvm.declaredRunner;
        firebreak-internal-runner-test-cloud = mkRunnerPackage self.nixosConfigurations.firebreak-cloud-smoke.config.microvm.declaredRunner;
        firebreak-codex = mkAgentPackage {
          name = "firebreak-codex";
          runnerPackage = "firebreak-internal-runner-codex";
          controlSocketName = "firebreak-codex";
          defaultAgentCommand = "codex";
          agentConfigDirName = ".codex";
          defaultAgentConfigHostDir = "$HOME/.codex";
        };
        firebreak-test-smoke-codex = mkSmokePackage {
          name = "firebreak-test-smoke-codex";
          agentPackage = "firebreak-codex";
          agentBin = "codex";
          agentDisplayName = "Codex";
          agentConfigDirName = ".codex";
        };
        firebreak-test-smoke-codex-version = mkAgentVersionSmokePackage {
          name = "firebreak-test-smoke-codex-version";
          agentPackage = "firebreak-codex";
          agentDisplayName = "Codex";
        };
        firebreak-claude-code = mkAgentPackage {
          name = "firebreak-claude-code";
          runnerPackage = "firebreak-internal-runner-claude-code";
          controlSocketName = "firebreak-claude-code";
          defaultAgentCommand = "claude";
          agentConfigDirName = ".claude";
          defaultAgentConfigHostDir = "$HOME/.claude";
        };
        firebreak-test-smoke-claude-code = mkSmokePackage {
          name = "firebreak-test-smoke-claude-code";
          agentPackage = "firebreak-claude-code";
          agentBin = "claude";
          agentDisplayName = "Claude Code";
          agentConfigDirName = ".claude";
        };
        firebreak-internal-job-codex-cloud = mkCloudJobPackage {
          name = "firebreak-internal-job-codex-cloud";
          runnerName = "firebreak-internal-runner-codex-cloud";
          defaultStateDir = "$HOME/.firebreak/firebreak-codex-cloud";
        };
        firebreak-internal-job-claude-code-cloud = mkCloudJobPackage {
          name = "firebreak-internal-job-claude-code-cloud";
          runnerName = "firebreak-internal-runner-claude-code-cloud";
          defaultStateDir = "$HOME/.firebreak/firebreak-claude-code-cloud";
        };
        firebreak-internal-job-test-cloud = mkCloudJobPackage {
          name = "firebreak-internal-job-test-cloud";
          runnerName = "firebreak-internal-runner-test-cloud";
          defaultStateDir = "$HOME/.firebreak/firebreak-cloud-smoke";
        };
        firebreak-test-smoke-cloud-job = mkCloudSmokePackage {
          name = "firebreak-test-smoke-cloud-job";
          jobPackage = "firebreak-internal-job-test-cloud";
        };
        firebreak-internal-validate = mkValidationPackage {
          name = "firebreak-internal-validate";
        };
        firebreak-test-smoke-internal-validate = mkValidationSmokePackage {
          name = "firebreak-test-smoke-internal-validate";
          validatePackage = "firebreak-internal-validate";
        };
        firebreak-internal-task = mkTaskPackage {
          name = "firebreak-internal-task";
        };
        firebreak-test-smoke-internal-task = mkTaskSmokePackage {
          name = "firebreak-test-smoke-internal-task";
        };
        firebreak-internal-loop = mkLoopPackage {
          name = "firebreak-internal-loop";
          taskPackage = "firebreak-internal-task";
        };
        firebreak-test-smoke-internal-loop = mkLoopSmokePackage {
          name = "firebreak-test-smoke-internal-loop";
        };
        firebreak = mkFirebreakCliPackage {
          name = "firebreak";
          validatePackage = "firebreak-internal-validate";
          taskPackage = "firebreak-internal-task";
          loopPackage = "firebreak-internal-loop";
        };
      };

      checks.${system} = {
        firebreak-internal-runner-codex = self.packages.${system}.firebreak-internal-runner-codex;
        firebreak-codex-system = self.nixosConfigurations.firebreak-codex.config.system.build.toplevel;
        firebreak-test-smoke-codex = self.packages.${system}.firebreak-test-smoke-codex;
        firebreak-internal-runner-codex-cloud = self.packages.${system}.firebreak-internal-runner-codex-cloud;
        firebreak-codex-cloud-system = self.nixosConfigurations.firebreak-codex-cloud.config.system.build.toplevel;
        firebreak-test-smoke-cloud-job = self.packages.${system}.firebreak-test-smoke-cloud-job;
        firebreak-test-smoke-internal-loop = self.packages.${system}.firebreak-test-smoke-internal-loop;
        firebreak-test-smoke-internal-task = self.packages.${system}.firebreak-test-smoke-internal-task;
        firebreak-test-smoke-internal-validate = self.packages.${system}.firebreak-test-smoke-internal-validate;
        firebreak-internal-runner-claude-code = self.packages.${system}.firebreak-internal-runner-claude-code;
        firebreak-claude-code-system = self.nixosConfigurations.firebreak-claude-code.config.system.build.toplevel;
        firebreak-test-smoke-claude-code = self.packages.${system}.firebreak-test-smoke-claude-code;
        firebreak-internal-runner-claude-code-cloud = self.packages.${system}.firebreak-internal-runner-claude-code-cloud;
        firebreak-claude-code-cloud-system = self.nixosConfigurations.firebreak-claude-code-cloud.config.system.build.toplevel;
        firebreak-internal-runner-test-cloud = self.packages.${system}.firebreak-internal-runner-test-cloud;
        firebreak-test-smoke-cloud-system = self.nixosConfigurations.firebreak-cloud-smoke.config.system.build.toplevel;
      };
    };
}
