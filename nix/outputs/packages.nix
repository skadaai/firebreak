{
  self,
  system,
  hostIsLinux,
  lib,
  localVmArtifacts,
  mkAgentPackage,
  mkAgentVersionSmokePackage,
  mkCloudJobPackage,
  mkCloudSmokePackage,
  mkDevFlowCliPackage,
  mkDevFlowCliSurfaceSmokePackage,
  mkFirebreakCliSurfaceSmokePackage,
  mkWorkerFirebreakBridgeProbePackage,
  mkFirebreakCliPackage,
  mkLoopPackage,
  mkLoopSmokePackage,
  mkNpxLauncherSmokePackage,
  mkProjectConfigSmokePackage,
  mkRunnerPackage,
  mkSmokePackage,
  mkWorkspacePackage,
  mkWorkspaceSmokePackage,
  mkValidationPackage,
  mkValidationSmokePackage,
  mkWorkerFirebreakAttachSmokePackage,
  mkWorkerInteractiveClaudeDirectExitSmokePackage,
  mkWorkerInteractiveClaudeDirectSmokePackage,
  mkWorkerInteractiveCodexDirectSmokePackage,
  mkWorkerGuestBridgeInteractiveSmokePackage,
  mkWorkerGuestBridgeSmokePackage,
  mkWorkerPackage,
  mkWorkerProxyScriptSmokePackage,
  mkWorkerSmokePackage,
}:
{
  default = self.packages.${system}.firebreak;

  firebreak-internal-runner-codex = localVmArtifacts.firebreak-codex.runnerPackage;
  firebreak-internal-runner-claude-code = localVmArtifacts.firebreak-claude-code.runnerPackage;
  firebreak-internal-runner-interactive-echo = localVmArtifacts.firebreak-interactive-echo.runnerPackage;

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

  firebreak-interactive-echo = localVmArtifacts.firebreak-interactive-echo.package;

  firebreak-test-smoke-project-config-and-doctor = mkProjectConfigSmokePackage {
    name = "firebreak-test-smoke-project-config-and-doctor";
  };

  firebreak-test-smoke-npx-launcher = mkNpxLauncherSmokePackage {
    name = "firebreak-test-smoke-npx-launcher";
  };

  firebreak-test-smoke-firebreak-cli-surface = mkFirebreakCliSurfaceSmokePackage {
    name = "firebreak-test-smoke-firebreak-cli-surface";
  };

  dev-flow-test-smoke-cli-surface = mkDevFlowCliSurfaceSmokePackage {
    name = "dev-flow-test-smoke-cli-surface";
  };

  firebreak-worker-bridge-probe = mkWorkerFirebreakBridgeProbePackage {
    name = "firebreak-worker-bridge-probe";
  };

  firebreak-test-smoke-worker-proxy-script = mkWorkerProxyScriptSmokePackage {
    name = "firebreak-test-smoke-worker-proxy-script";
  };

  dev-flow-validate = mkValidationPackage {
    name = "dev-flow-validate";
    includeCloudSuite = hostIsLinux;
  };

  dev-flow-test-smoke-validate = mkValidationSmokePackage {
    name = "dev-flow-test-smoke-validate";
    validatePackage = "dev-flow-validate";
  };

  dev-flow-workspace = mkWorkspacePackage {
    name = "dev-flow-workspace";
  };

  dev-flow-test-smoke-workspace = mkWorkspaceSmokePackage {
    name = "dev-flow-test-smoke-workspace";
  };

  firebreak-worker = mkWorkerPackage {
    name = "firebreak-worker";
  };

  firebreak-test-smoke-worker = mkWorkerSmokePackage {
    name = "firebreak-test-smoke-worker";
    workerPackage = "firebreak-worker";
  };

  firebreak-test-smoke-worker-firebreak-attach = mkWorkerFirebreakAttachSmokePackage {
    name = "firebreak-test-smoke-worker-firebreak-attach";
    workerPackage = "firebreak-worker";
  };

  firebreak-test-smoke-worker-interactive-claude-direct = mkWorkerInteractiveClaudeDirectSmokePackage {
    name = "firebreak-test-smoke-worker-interactive-claude-direct";
    firebreakPackage = "firebreak";
  };

  firebreak-test-smoke-worker-interactive-claude-exit-direct = mkWorkerInteractiveClaudeDirectExitSmokePackage {
    name = "firebreak-test-smoke-worker-interactive-claude-exit-direct";
    firebreakPackage = "firebreak";
  };

  firebreak-test-smoke-worker-interactive-codex-direct = mkWorkerInteractiveCodexDirectSmokePackage {
    name = "firebreak-test-smoke-worker-interactive-codex-direct";
    firebreakPackage = "firebreak";
  };

  firebreak-test-smoke-worker-guest-bridge = mkWorkerGuestBridgeSmokePackage {
    name = "firebreak-test-smoke-worker-guest-bridge";
  };

  firebreak-test-smoke-worker-guest-bridge-interactive = mkWorkerGuestBridgeInteractiveSmokePackage {
    name = "firebreak-test-smoke-worker-guest-bridge-interactive";
  };

  dev-flow-loop = mkLoopPackage {
    name = "dev-flow-loop";
    workspacePackage = "dev-flow-workspace";
  };

  dev-flow-test-smoke-loop = mkLoopSmokePackage {
    name = "dev-flow-test-smoke-loop";
  };

  firebreak = mkFirebreakCliPackage {
    name = "firebreak";
  };

  dev-flow = mkDevFlowCliPackage {
    name = "dev-flow";
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
