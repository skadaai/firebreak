{
  self,
  system,
  mkAgentPackage,
  mkAgentVersionSmokePackage,
  mkCloudJobPackage,
  mkCloudSmokePackage,
  mkFirebreakCliSurfaceSmokePackage,
  mkFirebreakCliPackage,
  mkLoopPackage,
  mkLoopSmokePackage,
  mkNpxLauncherSmokePackage,
  mkProjectConfigSmokePackage,
  mkRunnerPackage,
  mkSmokePackage,
  mkTaskPackage,
  mkTaskSmokePackage,
  mkValidationPackage,
  mkValidationSmokePackage,
  mkWorkerFirebreakAttachSmokePackage,
  mkWorkerGuestBridgeInteractiveSmokePackage,
  mkWorkerGuestBridgeSmokePackage,
  mkWorkerPackage,
  mkWorkerSmokePackage,
}:
{
  default = self.packages.${system}.firebreak;

  firebreak-internal-runner-codex = mkRunnerPackage self.nixosConfigurations.firebreak-codex.config.microvm.declaredRunner;
  firebreak-internal-runner-claude-code = mkRunnerPackage self.nixosConfigurations.firebreak-claude-code.config.microvm.declaredRunner;
  firebreak-internal-runner-interactive-echo = mkRunnerPackage self.nixosConfigurations.firebreak-interactive-echo.config.microvm.declaredRunner;
  firebreak-internal-runner-codex-cloud = mkRunnerPackage self.nixosConfigurations.firebreak-codex-cloud.config.microvm.declaredRunner;
  firebreak-internal-runner-claude-code-cloud = mkRunnerPackage self.nixosConfigurations.firebreak-claude-code-cloud.config.microvm.declaredRunner;
  firebreak-internal-runner-test-cloud = mkRunnerPackage self.nixosConfigurations.firebreak-cloud-smoke.config.microvm.declaredRunner;

  firebreak-codex = mkAgentPackage {
    name = "firebreak-codex";
    runner = self.packages.${system}.firebreak-internal-runner-codex;
    controlSocketName = "firebreak-codex";
    defaultAgentCommand = "codex";
    agentConfigDirName = ".codex";
    defaultAgentConfigHostDir = "$HOME/.codex";
    agentEnvPrefix = "CODEX";
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
    runner = self.packages.${system}.firebreak-internal-runner-claude-code;
    controlSocketName = "firebreak-claude-code";
    defaultAgentCommand = "claude";
    agentConfigDirName = ".claude";
    defaultAgentConfigHostDir = "$HOME/.claude";
    agentEnvPrefix = "CLAUDE";
  };

  firebreak-test-smoke-claude-code = mkSmokePackage {
    name = "firebreak-test-smoke-claude-code";
    agentPackage = "firebreak-claude-code";
    agentBin = "claude";
    agentDisplayName = "Claude Code";
    agentConfigDirName = ".claude";
  };

  firebreak-interactive-echo = mkAgentPackage {
    name = "firebreak-interactive-echo";
    runner = self.packages.${system}.firebreak-internal-runner-interactive-echo;
    controlSocketName = "firebreak-interactive-echo";
    defaultAgentCommand = "interactive-echo";
    agentConfigDirName = ".firebreak";
    defaultAgentConfigHostDir = "$HOME/.firebreak/firebreak-interactive-echo";
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

  firebreak-test-smoke-project-config-and-doctor = mkProjectConfigSmokePackage {
    name = "firebreak-test-smoke-project-config-and-doctor";
  };

  firebreak-test-smoke-npx-launcher = mkNpxLauncherSmokePackage {
    name = "firebreak-test-smoke-npx-launcher";
  };

  firebreak-test-smoke-firebreak-cli-surface = mkFirebreakCliSurfaceSmokePackage {
    name = "firebreak-test-smoke-firebreak-cli-surface";
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

  firebreak-worker = mkWorkerPackage {
    name = "firebreak-worker";
  };

  firebreak-test-smoke-internal-task = mkTaskSmokePackage {
    name = "firebreak-test-smoke-internal-task";
  };

  firebreak-test-smoke-worker = mkWorkerSmokePackage {
    name = "firebreak-test-smoke-worker";
    workerPackage = "firebreak-worker";
  };

  firebreak-test-smoke-worker-firebreak-attach = mkWorkerFirebreakAttachSmokePackage {
    name = "firebreak-test-smoke-worker-firebreak-attach";
    workerPackage = "firebreak-worker";
  };

  firebreak-test-smoke-worker-guest-bridge = mkWorkerGuestBridgeSmokePackage {
    name = "firebreak-test-smoke-worker-guest-bridge";
  };

  firebreak-test-smoke-worker-guest-bridge-interactive = mkWorkerGuestBridgeInteractiveSmokePackage {
    name = "firebreak-test-smoke-worker-guest-bridge-interactive";
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
  };
}
