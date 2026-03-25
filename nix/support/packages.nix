{ self, system, pkgs, renderTemplate, mkLocalVmArtifacts }:
{
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
      } ../../modules/base/tests/agent-smoke.sh;
    };

  mkProjectConfigSmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnugrep
        python3
      ];
      text = renderTemplate {
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-project-config-and-doctor.sh;
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
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-npx-launcher.sh;
    };

  mkFirebreakCliSurfaceSmokePackage = { name }:
    let
      fakeNix = pkgs.writeShellScriptBin "nix" ''
        set -eu

        if [ "$#" -gt 0 ] && [ "$1" = "--version" ]; then
          printf '%s\n' 'nix smoke shim'
          exit 0
        fi

        while [ "$#" -gt 0 ] && [ "$1" != "run" ]; do
          shift
        done

        [ "$#" -gt 0 ] || exit 1
        shift
        installable=''${1:-}
        shift

        if [ "''${1:-}" = "--" ]; then
          shift
        fi

        case "$installable" in
          *"#firebreak-codex")
            printf '%s\n' "__VM__codex"
            printf '%s\n' "__MODE__''${FIREBREAK_VM_MODE:-unset}"
            ;;
          *"#firebreak-claude-code")
            printf '%s\n' "__VM__claude-code"
            printf '%s\n' "__MODE__''${FIREBREAK_VM_MODE:-unset}"
            ;;
          *"#firebreak-internal-validate")
            printf '%s\n' "__INTERNAL__validate"
            ;;
          *"#firebreak-internal-task")
            printf '%s\n' "__INTERNAL__task"
            ;;
          *"#firebreak-internal-loop")
            printf '%s\n' "__INTERNAL__loop"
            ;;
          *"#firebreak-worker")
            printf '%s\n' "__WORKER__broker"
            ;;
          *)
            printf '%s\n' "__INSTALLABLE__$installable"
            ;;
        esac

        for arg in "$@"; do
          printf '%s\n' "__ARG__$arg"
        done
      '';
      fakeCli = pkgs.writeShellApplication {
        name = "firebreak-cli-smoke-firebreak";
        runtimeInputs = with pkgs; [
          bash
          coreutils
          git
          gnugrep
          gnused
          python3
          fakeNix
        ];
        text = ''
          export FIREBREAK_LIBEXEC_DIR='${builtins.toString ../../modules/base/host}'
          export FIREBREAK_FLAKE_REF='path:/firebreak-cli-smoke'
          exec bash "$FIREBREAK_LIBEXEC_DIR/firebreak.sh" "$@"
        '';
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
        python3
      ];
      text = renderTemplate {
        "@FIREBREAK_CLI_BIN@" = "${fakeCli}/bin/firebreak-cli-smoke-firebreak";
      } ../../modules/base/tests/test-smoke-firebreak-cli-surface.sh;
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
      } ../../modules/profiles/cloud/host/run-job.sh;
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
      } ../../modules/profiles/cloud/tests/test-smoke-cloud-job.sh;
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
      } ../../modules/base/host/firebreak-validate.sh;
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
      } ../../modules/base/tests/agent-version-smoke.sh;
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
      } ../../modules/base/tests/test-smoke-internal-validate.sh;
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
      text = builtins.readFile ../../modules/base/host/firebreak-task.sh;
    };

  mkWorkerPackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnused
      ];
      text = builtins.readFile ../../modules/base/host/firebreak-worker.sh;
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
      text = builtins.readFile ../../modules/base/tests/test-smoke-internal-task.sh;
    };

  mkWorkerSmokePackage = { name, workerPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
      ];
      text = renderTemplate {
        "@AGENT_BIN@" = "${self.packages.${system}.${workerPackage}}/bin/${workerPackage}";
      } ../../modules/base/tests/test-smoke-worker.sh;
    };

  mkWorkerGuestBridgeSmokePackage = { name }:
    let
      bridgeVm = mkLocalVmArtifacts {
        name = "firebreak-worker-guest-bridge-smoke-vm";
        defaultAgentCommand = "bash";
        workerBridgeEnabled = true;
        workerKinds = {
          bridge-process = {
            backend = "process";
            command = [ "sh" "-c" "printf guest-bridge-ok" ];
          };
          bridge-stop = {
            backend = "process";
            command = [ "sh" "-c" "sleep 30" ];
          };
          bridge-firebreak = {
            backend = "firebreak";
            package = "firebreak-codex";
            vm_mode = "run";
          };
        };
        extraModules = [
          ({ pkgs, ... }: {
            agentVm.extraSystemPackages = with pkgs; [
              gnugrep
              gnused
              python3
            ];
          })
        ];
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
      ];
      text = renderTemplate {
        "@BRIDGE_VM_BIN@" = "${bridgeVm.package}/bin/firebreak-worker-guest-bridge-smoke-vm";
      } ../../modules/base/tests/test-smoke-worker-guest-bridge.sh;
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
      } ../../modules/base/host/firebreak-loop.sh;
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
      text = builtins.readFile ../../modules/base/tests/test-smoke-internal-loop.sh;
    };

  mkFirebreakCliPackage = { name }:
    let
      firebreakLibexec = pkgs.runCommand "firebreak-libexec" {} ''
        mkdir -p "$out/libexec"
        install -m 0555 ${../../modules/base/host/firebreak.sh} "$out/libexec/firebreak.sh"
        install -m 0555 ${../../modules/base/host/firebreak-init.sh} "$out/libexec/firebreak-init.sh"
        install -m 0555 ${../../modules/base/host/firebreak-doctor.sh} "$out/libexec/firebreak-doctor.sh"
        install -m 0555 ${../../modules/base/host/firebreak-project-config.sh} "$out/libexec/firebreak-project-config.sh"
      '';
      firebreakFlakeRef = "path:${builtins.toString ../../.}";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnused
        nix
        python3
      ];
      text = ''
        export FIREBREAK_LIBEXEC_DIR='${firebreakLibexec}/libexec'
        export FIREBREAK_FLAKE_REF='${firebreakFlakeRef}'
        exec bash "$FIREBREAK_LIBEXEC_DIR/firebreak.sh" "$@"
      '';
    };
}
