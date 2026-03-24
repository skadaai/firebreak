{ self, system, pkgs, renderTemplate }:
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

  mkFirebreakCliPackage = { name, validatePackage, taskPackage, loopPackage }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ coreutils ];
      text = renderTemplate {
        "@VALIDATE_BIN@" = "${self.packages.${system}.${validatePackage}}/bin/${validatePackage}";
        "@TASK_BIN@" = "${self.packages.${system}.${taskPackage}}/bin/${taskPackage}";
        "@LOOP_BIN@" = "${self.packages.${system}.${loopPackage}}/bin/${loopPackage}";
      } ../../modules/base/host/firebreak.sh;
    };
}
