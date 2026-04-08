{ self, system, pkgs, renderTemplate, mkLocalVmArtifacts }:
rec {
  mkFirebreakLibexecPackage =
    pkgs.runCommand "firebreak-libexec" {} ''
      mkdir -p "$out/libexec"
      install -m 0555 ${../../modules/base/host/firebreak.sh} "$out/libexec/firebreak.sh"
      install -m 0555 ${../../modules/base/host/firebreak-init.sh} "$out/libexec/firebreak-init.sh"
      install -m 0555 ${../../modules/base/host/firebreak-doctor.sh} "$out/libexec/firebreak-doctor.sh"
      install -m 0555 ${../../modules/base/host/firebreak-environment.sh} "$out/libexec/firebreak-environment.sh"
      install -m 0555 ${../../modules/base/host/firebreak-project-config.sh} "$out/libexec/firebreak-project-config.sh"
      install -m 0555 ${../../modules/base/host/firebreak-worker.sh} "$out/libexec/firebreak-worker.sh"
    '';

  mkSmokePackage = {
    name,
    agentPackage,
    agentBin,
    agentDisplayName,
    agentConfigSubdir,
    defaultAgentConfigHostDir,
    workspaceBootstrapConfigHostDir,
  }:
    let
      agentConfigDirName = ".firebreak/${agentConfigSubdir}";
    in
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
        "@STATE_DIR_NAME@" = agentConfigDirName;
        "@STATE_SUBDIR@" = agentConfigSubdir;
        "@VM_STATE_ROOT@" = "/home/dev";
        "@AGENT_DISPLAY_NAME@" = agentDisplayName;
        "@AGENT_PACKAGE@" = agentPackage;
        "@DEFAULT_STATE_ROOT@" = defaultAgentConfigHostDir;
        "@WORKSPACE_BOOTSTRAP_CONFIG_HOST_DIR@" = workspaceBootstrapConfigHostDir;
      } ../../modules/base/tests/agent-smoke.sh;
    };

  mkProjectConfigSmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnugrep
        gnused
        python3
      ];
      text = renderTemplate {
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-project-config-and-doctor.sh;
    };

  mkCredentialSlotSmokePackage = {
    name,
    fixturePackage,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnugrep
      ];
      text = renderTemplate {
        "@FIXTURE_PACKAGE_BIN@" = "${self.packages.${system}.${fixturePackage}}/bin/${fixturePackage}";
      } ../../modules/base/tests/test-smoke-credential-slots.sh;
    };

  mkToolCredentialSlotSmokePackage = {
    name,
    agentPackage,
    agentBin,
    agentDisplayName,
    agentConfigSubdir,
    authFile,
    apiKeyFile,
    apiKeyEnv,
    configRootEnv,
    credentialSlotSpecificVar,
    loginCommand,
    loginCommandArgs,
  }:
    let
      renderShellArray = values:
        builtins.concatStringsSep "\n" (map (value: "  ${builtins.toJSON value}") values);
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnugrep
      ];
      text = renderTemplate {
        "@AGENT_PACKAGE@" = agentPackage;
        "@AGENT_BIN@" = agentBin;
        "@AGENT_DISPLAY_NAME@" = agentDisplayName;
        "@STATE_SUBDIR@" = agentConfigSubdir;
        "@AUTH_FILE@" = authFile;
        "@API_KEY_FILE@" = apiKeyFile;
        "@API_KEY_ENV@" = apiKeyEnv;
        "@CONFIG_ROOT_ENV@" = configRootEnv;
        "@CREDENTIAL_SLOT_SPECIFIC_VAR@" = credentialSlotSpecificVar;
        "@LOGIN_COMMAND@" = loginCommand;
        "@LOGIN_COMMAND_ARGS@" = renderShellArray loginCommandArgs;
      } ../../modules/base/tests/test-smoke-tool-credential-slots.sh;
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
            printf '%s\n' "__MODE__''${FIREBREAK_LAUNCH_MODE:-unset}"
            printf '%s\n' "__WORKER_MODE__''${FIREBREAK_WORKER_MODE:-unset}"
            printf '%s\n' "__WORKER_MODES__''${FIREBREAK_WORKER_MODES:-unset}"
            ;;
          *"#firebreak-claude-code")
            printf '%s\n' "__VM__claude-code"
            printf '%s\n' "__MODE__''${FIREBREAK_LAUNCH_MODE:-unset}"
            printf '%s\n' "__WORKER_MODE__''${FIREBREAK_WORKER_MODE:-unset}"
            printf '%s\n' "__WORKER_MODES__''${FIREBREAK_WORKER_MODES:-unset}"
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
        gnused
        python3
      ];
      text = renderTemplate {
        "@FIREBREAK_CLI_BIN@" = "${fakeCli}/bin/firebreak-cli-smoke-firebreak";
      } ../../modules/base/tests/test-smoke-firebreak-cli-surface.sh;
    };

  mkWorkerFirebreakBridgeProbePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ coreutils ];
      text = ''
        set -eu

        printf '%s\n' 'bridge-firebreak-ok'
        for arg in "$@"; do
          printf 'arg:%s\n' "$arg"
        done
      '';
    };

  mkWorkerProxyScriptSmokePackage = { name }:
    let
      workerProxyScript = self.lib.${system}.mkWorkerProxyScript {
        commandName = "codex";
        kind = "codex";
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
        "@WORKER_PROXY_SCRIPT@" = workerProxyScript;
      } ../../modules/base/tests/test-smoke-worker-proxy-script.sh;
    };

  mkLocalControllerSmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        diffutils
        gnused
      ];
      text = renderTemplate {
        "@LOCAL_CONTROLLER_LIB@" = builtins.toString ../../modules/profiles/local/host/local-instance-controller.sh;
      } ../../modules/profiles/local/tests/test-smoke-local-controller.sh;
    };

  mkCloudHypervisorEgressProxySmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        python3
      ];
      text = renderTemplate {
        "@PROXY_SCRIPT@" = builtins.toString ../../modules/profiles/local/host/cloud-hypervisor-egress-proxy.py;
      } ../../modules/profiles/local/tests/test-smoke-cloud-hypervisor-egress-proxy.sh;
    };

  mkCloudHypervisorPortPublishSmokePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        python3
      ];
      text = renderTemplate {
        "@PROXY_SCRIPT@" = builtins.toString ../../modules/profiles/local/host/cloud-hypervisor-port-publish.py;
      } ../../modules/profiles/local/tests/test-smoke-cloud-hypervisor-port-publish.sh;
    };

  mkPortPublishRuntimeSmokePackage = { name, fixturePackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        python3
      ];
      text = renderTemplate {
        "@FIXTURE_PACKAGE_BIN@" = "${self.packages.${system}.${fixturePackage}}/bin/${fixturePackage}";
      } ../../modules/profiles/local/tests/test-smoke-port-publish-runtime.sh;
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

  mkValidationPackage = { name, includeCloudSuite ? true }:
    let
      cloudSmokeBin =
        if includeCloudSuite then
          "${self.packages.${system}.firebreak-test-smoke-cloud-job}/bin/firebreak-test-smoke-cloud-job"
        else
          "";
      cloudSuiteCase =
        if includeCloudSuite then
          ''
  test-smoke-cloud-job)
    suite_command="${cloudSmokeBin}"
    ;;
''
        else
          "";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        gnused
        iproute2
        iptables
        sudo
      ];
      text = renderTemplate {
        "@LOCAL_CONTROLLER_SMOKE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-local-controller}/bin/firebreak-test-smoke-local-controller";
        "@CODEX_SMOKE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-codex}/bin/firebreak-test-smoke-codex";
        "@CODEX_VERSION_BIN@" = "${self.packages.${system}.firebreak-test-smoke-codex-version}/bin/firebreak-test-smoke-codex-version";
        "@CODEX_WARM_REUSE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-codex-warm-reuse}/bin/firebreak-test-smoke-codex-warm-reuse";
        "@CLAUDE_SMOKE_BIN@" = "${self.packages.${system}.firebreak-test-smoke-claude-code}/bin/firebreak-test-smoke-claude-code";
        "@PORT_PUBLISH_RUNTIME_BIN@" = "${self.packages.${system}.firebreak-test-smoke-port-publish-runtime}/bin/firebreak-test-smoke-port-publish-runtime";
        "@CLOUD_SMOKE_BIN@" = cloudSmokeBin;
        "@CLOUD_SUITE_USAGE@" =
          if includeCloudSuite then
            "  test-smoke-cloud-job"
          else
            "";
        "@CLOUD_SUITE_CASE@" = cloudSuiteCase;
      } ../../modules/base/host/firebreak-validate.sh;
    };

  mkWorkloadVersionSmokePackage = {
    name,
    agentPackage,
    agentDisplayName,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnugrep
        gnused
        python3
      ];
      text = renderTemplate {
        "@AGENT_PACKAGE_BIN@" = "${self.packages.${system}.${agentPackage}}/bin/${agentPackage}";
        "@AGENT_DISPLAY_NAME@" = agentDisplayName;
        "@PROFILE_SUMMARY_SCRIPT@" = builtins.toString ../../modules/profiles/local/host/profile-summary.py;
        "@PYTHON3@" = "${pkgs.python3}/bin/python3";
      } ../../modules/base/tests/agent-version-smoke.sh;
    };

  mkWorkloadWarmReuseSmokePackage = {
    name,
    agentPackage,
    agentDisplayName,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        findutils
        git
        gnugrep
        python3
      ];
      text = renderTemplate {
        "@AGENT_PACKAGE_BIN@" = "${self.packages.${system}.${agentPackage}}/bin/${agentPackage}";
        "@AGENT_DISPLAY_NAME@" = agentDisplayName;
      } ../../modules/base/tests/agent-warm-reuse-smoke.sh;
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
        findutils
        gawk
        gnused
        nix
        python3
      ];
      text = ''
        export FIREBREAK_LIBEXEC_DIR='${mkFirebreakLibexecPackage}/libexec'
        exec bash "$FIREBREAK_LIBEXEC_DIR/firebreak-worker.sh" "$@"
      '';
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
    let
      smokeWorkerBin = pkgs.writeShellApplication {
        name = "${name}-worker-bin";
        runtimeInputs = with pkgs; [
          bash
          coreutils
          findutils
          gawk
          gnused
          python3
        ];
        text = ''
          export FIREBREAK_LIBEXEC_DIR='${mkFirebreakLibexecPackage}/libexec'
          exec bash "$FIREBREAK_LIBEXEC_DIR/firebreak-worker.sh" "$@"
        '';
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
        gnused
      ];
      text = renderTemplate {
        "@AGENT_BIN@" = "${smokeWorkerBin}/bin/${name}-worker-bin";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker.sh;
    };

  mkWorkerFirebreakAttachSmokePackage = { name, workerPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        python3
      ];
      text = renderTemplate {
        "@AGENT_BIN@" = "${self.packages.${system}.${workerPackage}}/bin/${workerPackage}";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-firebreak-attach.sh;
    };

  mkWorkerClaudeVersionSmokePackage = { name, firebreakPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
      ];
      text = renderTemplate {
        "@AGENT_BIN@" = "${self.packages.${system}.${firebreakPackage}}/bin/${firebreakPackage}";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-claude-version.sh;
    };

  mkWorkerInteractiveClaudeDirectSmokePackage = { name, firebreakPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        python3
      ];
      text = renderTemplate {
        "@FIREBREAK_BIN@" = "${self.packages.${system}.${firebreakPackage}}/bin/${firebreakPackage}";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-interactive-claude-direct.sh;
    };

  mkWorkerInteractiveClaudeDirectExitSmokePackage = { name, firebreakPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        python3
      ];
      text = renderTemplate {
        "@FIREBREAK_BIN@" = "${self.packages.${system}.${firebreakPackage}}/bin/${firebreakPackage}";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-interactive-claude-exit-direct.sh;
    };

  mkWorkerInteractiveCodexDirectSmokePackage = { name, firebreakPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        python3
      ];
      text = renderTemplate {
        "@FIREBREAK_BIN@" = "${self.packages.${system}.${firebreakPackage}}/bin/${firebreakPackage}";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-interactive-codex-direct.sh;
    };

  mkWorkerGuestBridgeArtifacts =
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
          bridge-limited = {
            backend = "process";
            command = [ "sh" "-c" "sleep 30" ];
            max_instances = 1;
          };
          bridge-firebreak = {
            backend = "firebreak";
            package = "firebreak-worker-bridge-probe";
            launch_mode = "run";
          };
          bridge-interactive-firebreak = {
            backend = "firebreak";
            package = "firebreak-interactive-echo";
            launch_mode = "run";
          };
        };
        extraModules = [
          ({ pkgs, ... }: {
            workloadVm.extraSystemPackages = with pkgs; [
              gnugrep
              gnused
              python3
              util-linux
            ];
            networking.firewall.enable = false;
          })
        ];
      };
    in
    bridgeVm;

  mkWorkerGuestBridgeSmokePackage = { name }:
    let
      bridgeVm = mkWorkerGuestBridgeArtifacts;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
      ];
      text = renderTemplate {
        "@AGENT_BIN@" = "${self.packages.${system}.firebreak}/bin/firebreak";
        "@BRIDGE_VM_BIN@" = "${bridgeVm.package}/bin/firebreak-worker-guest-bridge-smoke-vm";
        "@REPO_ROOT@" = builtins.toString ../../.;
        "@WORKER_LOCAL_STATE_DIR@" = "/home/dev/.local/state/firebreak/worker-local";
      } ../../modules/base/tests/test-smoke-worker-guest-bridge.sh;
    };

  mkWorkerGuestBridgeInteractiveSmokePackage = { name }:
    let
      bridgeVm = mkWorkerGuestBridgeArtifacts;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
        self.packages.${system}.firebreak-interactive-echo
      ];
      text = renderTemplate {
        "@AGENT_BIN@" = "${self.packages.${system}.firebreak}/bin/firebreak";
        "@BRIDGE_VM_BIN@" = "${bridgeVm.package}/bin/firebreak-worker-guest-bridge-smoke-vm";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-guest-bridge-interactive.sh;
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
      firebreakFlakeRef = "path:${builtins.toString ../../.}";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        findutils
        gawk
        git
        gnused
        iproute2
        iptables
        nix
        python3
        sudo
      ];
      text = ''
        export FIREBREAK_LIBEXEC_DIR='${mkFirebreakLibexecPackage}/libexec'
        export FIREBREAK_FLAKE_REF='${firebreakFlakeRef}'
        export FIREBREAK_NIXPKGS_PATH='${pkgs.path}'
        export FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG='1'
        export FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes'
        exec bash "$FIREBREAK_LIBEXEC_DIR/firebreak.sh" "$@"
      '';
    };
}
