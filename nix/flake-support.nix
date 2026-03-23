{ self, nixpkgs, microvm, system }:
let
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
    agentEnvPrefix,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ coreutils git virtiofsd ];
      text = renderTemplate {
        "@CONTROL_SOCKET@" = "${controlSocketName}.socket";
        "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
        "@RUNNER@" = "${self.packages.${system}.${runnerPackage}}/bin/microvm-run";
        "@AGENT_CONFIG_DIR_NAME@" = agentConfigDirName;
        "@DEFAULT_AGENT_CONFIG_HOST_DIR@" = defaultAgentConfigHostDir;
        "@AGENT_ENV_PREFIX@" = agentEnvPrefix;
        "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../modules/base/host/firebreak-project-config.sh;
      } ../modules/profiles/local/host/run-wrapper.sh;
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
      } ../modules/base/tests/agent-smoke.sh;
    };

  mkProjectConfigSmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnugrep
      ];
      text = renderTemplate {
        "@REPO_ROOT@" = builtins.toString ../.;
      } ../modules/base/tests/test-smoke-project-config-and-doctor.sh;
    };

  mkNpxLauncherSmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
        nodejs_20
      ];
      text = renderTemplate {
        "@REPO_ROOT@" = builtins.toString ../.;
      } ../modules/base/tests/test-smoke-npx-launcher.sh;
    };

  mkFirebreakCliSurfaceSmokePackage = { name }:
    let
      fakeValidate = pkgs.writeShellScriptBin "firebreak-cli-smoke-validate" ''
        exit 0
      '';
      fakeTask = pkgs.writeShellScriptBin "firebreak-cli-smoke-task" ''
        exit 0
      '';
      fakeLoop = pkgs.writeShellScriptBin "firebreak-cli-smoke-loop" ''
        exit 0
      '';
      fakeCodex = pkgs.writeShellScriptBin "firebreak-cli-smoke-codex" ''
        printf '%s\n' "__VM__codex"
        printf '%s\n' "__MODE__''${FIREBREAK_VM_MODE:-unset}"
        for arg in "$@"; do
          printf '%s\n' "__ARG__$arg"
        done
      '';
      fakeClaudeCode = pkgs.writeShellScriptBin "firebreak-cli-smoke-claude-code" ''
        printf '%s\n' "__VM__claude-code"
        printf '%s\n' "__MODE__''${FIREBREAK_VM_MODE:-unset}"
        for arg in "$@"; do
          printf '%s\n' "__ARG__$arg"
        done
      '';
      fakeCli = pkgs.writeShellApplication {
        name = "firebreak-cli-smoke-firebreak";
        runtimeInputs = with pkgs; [
          coreutils
          git
          gnused
        ];
        text = renderTemplate {
          "@VALIDATE_BIN@" = "${fakeValidate}/bin/firebreak-cli-smoke-validate";
          "@TASK_BIN@" = "${fakeTask}/bin/firebreak-cli-smoke-task";
          "@LOOP_BIN@" = "${fakeLoop}/bin/firebreak-cli-smoke-loop";
          "@CODEX_BIN@" = "${fakeCodex}/bin/firebreak-cli-smoke-codex";
          "@CLAUDE_CODE_BIN@" = "${fakeClaudeCode}/bin/firebreak-cli-smoke-claude-code";
          "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../modules/base/host/firebreak-project-config.sh;
          "@FIREBREAK_INIT_FUNCTIONS@" = builtins.readFile ../modules/base/host/firebreak-init.sh;
          "@FIREBREAK_DOCTOR_FUNCTIONS@" = builtins.readFile ../modules/base/host/firebreak-doctor.sh;
        } ../modules/base/host/firebreak.sh;
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
      ];
      text = renderTemplate {
        "@FIREBREAK_CLI_BIN@" = "${fakeCli}/bin/firebreak-cli-smoke-firebreak";
      } ../modules/base/tests/test-smoke-firebreak-cli-surface.sh;
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
      } ../modules/profiles/cloud/host/run-job.sh;
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
      } ../modules/profiles/cloud/tests/test-smoke-cloud-job.sh;
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
      } ../modules/base/host/firebreak-validate.sh;
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
      } ../modules/base/tests/agent-version-smoke.sh;
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
      } ../modules/base/tests/test-smoke-internal-validate.sh;
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
      text = builtins.readFile ../modules/base/host/firebreak-task.sh;
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
      text = builtins.readFile ../modules/base/tests/test-smoke-internal-task.sh;
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
      } ../modules/base/host/firebreak-loop.sh;
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
      text = builtins.readFile ../modules/base/tests/test-smoke-internal-loop.sh;
    };

  mkFirebreakCliPackage = { name, validatePackage, taskPackage, loopPackage, codexPackage, claudeCodePackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnused
        python3
      ];
      text = renderTemplate {
        "@VALIDATE_BIN@" = "${self.packages.${system}.${validatePackage}}/bin/${validatePackage}";
        "@TASK_BIN@" = "${self.packages.${system}.${taskPackage}}/bin/${taskPackage}";
        "@LOOP_BIN@" = "${self.packages.${system}.${loopPackage}}/bin/${loopPackage}";
        "@CODEX_BIN@" = "${self.packages.${system}.${codexPackage}}/bin/${codexPackage}";
        "@CLAUDE_CODE_BIN@" = "${self.packages.${system}.${claudeCodePackage}}/bin/${claudeCodePackage}";
        "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../modules/base/host/firebreak-project-config.sh;
        "@FIREBREAK_INIT_FUNCTIONS@" = builtins.readFile ../modules/base/host/firebreak-init.sh;
        "@FIREBREAK_DOCTOR_FUNCTIONS@" = builtins.readFile ../modules/base/host/firebreak-doctor.sh;
      } ../modules/base/host/firebreak.sh;
    };
in {
  inherit
    lib
    mkAgentPackage
    mkAgentVersionSmokePackage
    mkAgentVm
    mkCloudJobPackage
    mkCloudSmokePackage
    mkFirebreakCliSurfaceSmokePackage
    mkFirebreakCliPackage
    mkLoopPackage
    mkLoopSmokePackage
    mkNpxLauncherSmokePackage
    mkProjectConfigSmokePackage
    mkRunnerPackage
    mkSmokePackage
    mkTaskPackage
    mkTaskSmokePackage
    mkValidationPackage
    mkValidationSmokePackage
    pkgs
    renderTemplate
    ;
}
