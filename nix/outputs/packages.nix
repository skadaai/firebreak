{
  self,
  system,
  hostIsLinux,
  lib,
  localVmArtifacts,
  mkAgentVersionSmokePackage,
  mkCloudJobPackage,
  mkCloudSmokePackage,
  mkFirebreakCliSurfaceSmokePackage,
  mkFirebreakCliPackage,
  mkLoopPackage,
  mkLoopSmokePackage,
  mkNpxLauncherSmokePackage,
  mkProjectConfigSmokePackage,
  mkSmokePackage,
  mkTaskPackage,
  mkTaskSmokePackage,
  mkValidationPackage,
  mkValidationSmokePackage,
}:
{
  default = self.packages.${system}.firebreak;

  firebreak-internal-runner-codex = localVmArtifacts.firebreak-codex.runnerPackage;
  firebreak-internal-runner-claude-code = localVmArtifacts.firebreak-claude-code.runnerPackage;
  firebreak-codex = localVmArtifacts.firebreak-codex.package;

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

  firebreak-claude-code = localVmArtifacts.firebreak-claude-code.package;

  firebreak-test-smoke-claude-code = mkSmokePackage {
    name = "firebreak-test-smoke-claude-code";
    agentPackage = "firebreak-claude-code";
    agentBin = "claude";
    agentDisplayName = "Claude Code";
    agentConfigDirName = ".claude";
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
    includeCloudSuite = hostIsLinux;
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
  };
} // lib.optionalAttrs hostIsLinux {
  firebreak-internal-runner-codex-cloud = localVmArtifacts.firebreak-codex-cloud.runnerPackage;
  firebreak-internal-runner-claude-code-cloud = localVmArtifacts.firebreak-claude-code-cloud.runnerPackage;
  firebreak-internal-runner-test-cloud = localVmArtifacts.firebreak-cloud-smoke.runnerPackage;

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
}
