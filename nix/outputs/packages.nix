{
  self,
  system,
  hostIsLinux,
  lib,
  localVmArtifacts,
  mkWorkloadPackage,
  mkWorkloadVersionSmokePackage,
  mkCloudJobPackage,
  mkCloudSmokePackage,
  mkCredentialSlotSmokePackage,
  mkToolCredentialSlotSmokePackage,
  mkFirebreakCliSurfaceSmokePackage,
  mkWorkerFirebreakBridgeProbePackage,
  mkLocalControllerSmokePackage,
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
    agentConfigSubdir = "codex";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.codex";
  };

  firebreak-test-smoke-codex-version = mkWorkloadVersionSmokePackage {
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
    agentConfigSubdir = "claude";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.claude";
  };

  firebreak-interactive-echo = localVmArtifacts.firebreak-interactive-echo.package;

  firebreak-credential-fixture = localVmArtifacts.firebreak-credential-fixture.package;

  firebreak-test-smoke-credential-slots = mkCredentialSlotSmokePackage {
    name = "firebreak-test-smoke-credential-slots";
    fixturePackage = "firebreak-credential-fixture";
  };

  firebreak-test-smoke-codex-credential-slots = mkToolCredentialSlotSmokePackage {
    name = "firebreak-test-smoke-codex-credential-slots";
    agentPackage = "firebreak-codex";
    agentBin = "codex";
    agentDisplayName = "Codex";
    agentConfigSubdir = "codex";
    authFile = "auth.json";
    apiKeyFile = "OPENAI_API_KEY";
    apiKeyEnv = "OPENAI_API_KEY";
    configRootEnv = "CODEX_HOME";
    credentialSlotSpecificVar = "CODEX_CREDENTIAL_SLOT";
    loginCommand = "login";
    loginCommandArgs = [ "login" ];
  };

  firebreak-test-smoke-claude-code-credential-slots = mkToolCredentialSlotSmokePackage {
    name = "firebreak-test-smoke-claude-code-credential-slots";
    agentPackage = "firebreak-claude-code";
    agentBin = "claude";
    agentDisplayName = "Claude Code";
    agentConfigSubdir = "claude";
    authFile = ".credentials.json";
    apiKeyFile = "ANTHROPIC_API_KEY";
    apiKeyEnv = "ANTHROPIC_API_KEY";
    configRootEnv = "CLAUDE_CONFIG_DIR";
    credentialSlotSpecificVar = "CLAUDE_CREDENTIAL_SLOT";
    loginCommand = "auth login";
    loginCommandArgs = [ "auth" "login" ];
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

  firebreak-worker-bridge-probe = mkWorkerFirebreakBridgeProbePackage {
    name = "firebreak-worker-bridge-probe";
  };

  firebreak-test-smoke-worker-proxy-script = mkWorkerProxyScriptSmokePackage {
    name = "firebreak-test-smoke-worker-proxy-script";
  };

  firebreak-test-smoke-local-controller = mkLocalControllerSmokePackage {
    name = "firebreak-test-smoke-local-controller";
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
