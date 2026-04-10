{ self, system, pkgs, renderTemplate, mkLocalVmArtifacts }:
rec {
  writeUncheckedShellApplication = args:
    pkgs.writeShellApplication (args // {
      checkPhase = ":";
    });

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
    workloadPackage,
    toolBin,
    toolDisplayName,
    toolStateSubdir,
    defaultToolStateHostDir,
    workspaceBootstrapConfigHostDir,
  }:
    let
      toolStateDirName = ".firebreak/${toolStateSubdir}";
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
        "@TOOL_BIN@" = toolBin;
        "@STATE_DIR_NAME@" = toolStateDirName;
        "@STATE_SUBDIR@" = toolStateSubdir;
        "@VM_STATE_ROOT@" = "/home/dev";
        "@TOOL_DISPLAY_NAME@" = toolDisplayName;
        "@WORKLOAD_PACKAGE@" = workloadPackage;
        "@DEFAULT_STATE_ROOT@" = defaultToolStateHostDir;
        "@WORKSPACE_BOOTSTRAP_CONFIG_HOST_DIR@" = workspaceBootstrapConfigHostDir;
      } ../../modules/base/tests/tool-smoke.sh;
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
    workloadPackage,
    toolBin,
    toolDisplayName,
    toolStateSubdir,
    authFile,
    authFileFormat ? "opaque",
    apiKeyFile,
    apiKeyEnv,
    toolStateEnv,
    credentialSlotSpecificVar,
    loginCommand,
    loginCommandArgs,
  }:
    let
      renderShellArray = values:
        builtins.concatStringsSep "\n" (map (value: "  ${pkgs.lib.escapeShellArg value}") values);
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnugrep
        python3
      ];
      text = renderTemplate {
        "@WORKLOAD_PACKAGE@" = workloadPackage;
        "@TOOL_BIN@" = toolBin;
        "@TOOL_DISPLAY_NAME@" = toolDisplayName;
        "@STATE_SUBDIR@" = toolStateSubdir;
        "@AUTH_FILE@" = authFile;
        "@AUTH_FILE_FORMAT@" = authFileFormat;
        "@PYTHON3@" = "${pkgs.python3}/bin/python3";
        "@API_KEY_FILE@" = apiKeyFile;
        "@API_KEY_ENV@" = apiKeyEnv;
        "@CONFIG_ROOT_ENV@" = toolStateEnv;
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
        python3
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
      fakeWorkloadRegistry = pkgs.runCommand "firebreak-cli-smoke-workloads" {} ''
        mkdir -p "$out/bin"
        cat >"$out/bin/firebreak-codex" <<'EOF'
#!${pkgs.bash}/bin/bash
printf '%s\n' "__VM__codex"
printf '%s\n' "__MODE__''${FIREBREAK_LAUNCH_MODE:-unset}"
printf '%s\n' "__WORKER_MODE__''${FIREBREAK_WORKER_MODE:-unset}"
printf '%s\n' "__WORKER_MODES__''${FIREBREAK_WORKER_MODES:-unset}"
for arg in "$@"; do
  printf '%s\n' "__ARG__$arg"
done
EOF
        cat >"$out/bin/firebreak-claude-code" <<'EOF'
#!${pkgs.bash}/bin/bash
printf '%s\n' "__VM__claude-code"
printf '%s\n' "__MODE__''${FIREBREAK_LAUNCH_MODE:-unset}"
printf '%s\n' "__WORKER_MODE__''${FIREBREAK_WORKER_MODE:-unset}"
printf '%s\n' "__WORKER_MODES__''${FIREBREAK_WORKER_MODES:-unset}"
for arg in "$@"; do
  printf '%s\n' "__ARG__$arg"
done
EOF
        chmod 0555 "$out/bin/firebreak-codex" "$out/bin/firebreak-claude-code"
        cat >"$out/workloads.tsv" <<EOF
codex	Codex local Firebreak VM	$out/bin/firebreak-codex
claude-code	Claude Code local Firebreak VM	$out/bin/firebreak-claude-code
EOF
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
          export FIREBREAK_WORKLOAD_REGISTRY='${fakeWorkloadRegistry}/workloads.tsv'
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

  mkDevFlowCliSurfaceSmokePackage = { name }:
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
          *"#dev-flow-validate")
            printf '%s\n' "__DEV_FLOW__validate"
            ;;
          *"#dev-flow-workspace")
            printf '%s\n' "__DEV_FLOW__workspace"
            ;;
          *"#dev-flow-loop")
            printf '%s\n' "__DEV_FLOW__loop"
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
        name = "dev-flow-cli-smoke";
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
          export DEV_FLOW_LIBEXEC_DIR='${builtins.toString ../../modules/base/host}'
          export DEV_FLOW_FLAKE_REF='path:/dev-flow-cli-smoke'
          export DEV_FLOW_NIX_ACCEPT_FLAKE_CONFIG=1
          export DEV_FLOW_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes'
          exec bash "$DEV_FLOW_LIBEXEC_DIR/dev-flow.sh" "$@"
        '';
      };
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        gnugrep
      ];
      text = renderTemplate {
        "@DEV_FLOW_CLI_BIN@" = "${fakeCli}/bin/dev-flow-cli-smoke";
      } ../../modules/base/tests/test-smoke-dev-flow-cli-surface.sh;
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
      cloudSuiteCase =
        if includeCloudSuite then
          ''
  test-smoke-cloud-job)
    suite_package="firebreak-test-smoke-cloud-job"
    ;;
''
        else
          "";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnused
        nix
        sudo
      ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        iproute2
        iptables
      ];
      text = renderTemplate {
        "@CLOUD_SUITE_USAGE@" =
          if includeCloudSuite then
            "  test-smoke-cloud-job"
          else
            "";
        "@CLOUD_SUITE_CASE@" = cloudSuiteCase;
      } ../../modules/base/host/dev-flow-validate.sh;
    };

  mkValidationFixturePackage = {
    name,
    message ? name,
    exitCode ? 0,
  }:
    writeUncheckedShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ coreutils ];
      text = ''
        set -eu
        printf '%s\n' ${builtins.toJSON message}
        exit ${toString exitCode}
      '';
    };

  mkWorkloadVersionSmokePackage = {
    name,
    workloadPackage,
    toolDisplayName,
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
        "@WORKLOAD_PACKAGE_BIN@" = "${self.packages.${system}.${workloadPackage}}/bin/${workloadPackage}";
        "@TOOL_DISPLAY_NAME@" = toolDisplayName;
        "@PROFILE_SUMMARY_SCRIPT@" = builtins.toString ../../modules/profiles/local/host/profile-summary.py;
        "@PYTHON3@" = "${pkgs.python3}/bin/python3";
      } ../../modules/base/tests/tool-version-smoke.sh;
    };

  mkWorkloadWarmReuseSmokePackage = {
    name,
    workloadPackage,
    toolDisplayName,
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
        "@WORKLOAD_PACKAGE_BIN@" = "${self.packages.${system}.${workloadPackage}}/bin/${workloadPackage}";
        "@TOOL_DISPLAY_NAME@" = toolDisplayName;
      } ../../modules/base/tests/tool-warm-reuse-smoke.sh;
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
      } ../../modules/base/tests/test-smoke-dev-flow-validate.sh;
    };

  mkWorkspacePackage = { name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnused
        nix
      ];
      text = builtins.readFile ../../modules/base/host/dev-flow-workspace.sh;
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

  mkWorkspaceSmokePackage = { name }:
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
      text = builtins.readFile ../../modules/base/tests/test-smoke-dev-flow-workspace.sh;
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
        "@TOOL_BIN@" = "${smokeWorkerBin}/bin/${name}-worker-bin";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker.sh;
    };

  mkWorkerFirebreakAttachSmokePackage = { name, workerPackage }:
    writeUncheckedShellApplication {
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
        "@TOOL_BIN@" = "${self.packages.${system}.${workerPackage}}/bin/${workerPackage}";
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
        "@TOOL_BIN@" = "${self.packages.${system}.${firebreakPackage}}/bin/${firebreakPackage}";
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
        defaultToolCommand = "bash";
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
    writeUncheckedShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
      ];
      text = renderTemplate {
        "@TOOL_BIN@" = "${self.packages.${system}.firebreak-worker}/bin/firebreak-worker";
        "@BRIDGE_VM_BIN@" = "${bridgeVm.package}/bin/firebreak-worker-guest-bridge-smoke-vm";
        "@REPO_ROOT@" = builtins.toString ../../.;
        "@WORKER_LOCAL_STATE_DIR@" = "/home/dev/.local/state/firebreak/worker-local";
      } ../../modules/base/tests/test-smoke-worker-guest-bridge.sh;
    };

  mkWorkerGuestBridgeInteractiveSmokePackage = { name }:
    let
      bridgeVm = mkWorkerGuestBridgeArtifacts;
    in
    writeUncheckedShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        gnugrep
        self.packages.${system}.firebreak-interactive-echo
      ];
      text = renderTemplate {
        "@TOOL_BIN@" = "${self.packages.${system}.firebreak-worker}/bin/firebreak-worker";
        "@BRIDGE_VM_BIN@" = "${bridgeVm.package}/bin/firebreak-worker-guest-bridge-smoke-vm";
        "@REPO_ROOT@" = builtins.toString ../../.;
      } ../../modules/base/tests/test-smoke-worker-guest-bridge-interactive.sh;
    };

  mkLoopPackage = { name, workspacePackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnugrep
        gnused
      ];
      text = renderTemplate {
        "@WORKSPACE_BIN@" = "${self.packages.${system}.${workspacePackage}}/bin/${workspacePackage}";
      } ../../modules/base/host/dev-flow-loop.sh;
    };

  mkLoopSmokePackage = { name }:
    writeUncheckedShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnugrep
        gnused
      ];
      text = builtins.readFile ../../modules/base/tests/test-smoke-dev-flow-loop.sh;
    };

  mkFirebreakCliPackage = {
    name,
    publicWorkloads,
  }:
    let
      firebreakWorkloadRegistry = pkgs.writeText "firebreak-workloads.tsv" ''
${builtins.concatStringsSep "\n" (map (workload:
          "${workload.name}\t${workload.description}\t${workload.launcher}"
        ) publicWorkloads)}
      '';
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
        nix
        python3
        sudo
      ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        iproute2
        iptables
      ];
      text = ''
        export FIREBREAK_LIBEXEC_DIR='${mkFirebreakLibexecPackage}/libexec'
        export FIREBREAK_FLAKE_REF='${firebreakFlakeRef}'
        export FIREBREAK_NIXPKGS_PATH='${pkgs.path}'
        export FIREBREAK_WORKLOAD_REGISTRY='${firebreakWorkloadRegistry}'
        export FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG='1'
        export FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes'
        exec bash "$FIREBREAK_LIBEXEC_DIR/firebreak.sh" "$@"
      '';
    };

  mkDevFlowCliPackage = { name }:
    let
      devFlowLibexec = pkgs.runCommand "dev-flow-libexec" {} ''
        mkdir -p "$out/libexec"
        install -m 0555 ${../../modules/base/host/dev-flow.sh} "$out/libexec/dev-flow.sh"
        install -m 0555 ${../../modules/base/host/firebreak-project-config.sh} "$out/libexec/firebreak-project-config.sh"
      '';
      devFlowFlakeRef = "path:${builtins.toString ../../.}";
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
        export DEV_FLOW_LIBEXEC_DIR='${devFlowLibexec}/libexec'
        export DEV_FLOW_FLAKE_REF='${devFlowFlakeRef}'
        export DEV_FLOW_NIX_ACCEPT_FLAKE_CONFIG=1
        export DEV_FLOW_NIX_EXTRA_EXPERIMENTAL_FEATURES='nix-command flakes'
        exec bash "$DEV_FLOW_LIBEXEC_DIR/dev-flow.sh" "$@"
      '';
    };
}
