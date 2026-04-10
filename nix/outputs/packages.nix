{
  self,
  system,
  includeCloud ? false,
  hostIsLinux,
  lib,
  localVmArtifacts,
  mkWorkloadPackage,
  mkWorkloadWarmReuseSmokePackage,
  mkWorkloadVersionSmokePackage,
  mkCloudJobPackage,
  mkCloudSmokePackage,
  mkDevFlowCliPackage,
  mkDevFlowCliSurfaceSmokePackage,
  mkCredentialSlotSmokePackage,
  mkToolCredentialSlotSmokePackage,
  mkFirebreakCliSurfaceSmokePackage,
  mkWorkerFirebreakBridgeProbePackage,
  mkLocalControllerSmokePackage,
  mkCloudHypervisorEgressProxySmokePackage,
  mkCloudHypervisorPortPublishSmokePackage,
  mkPortPublishRuntimeSmokePackage,
  mkFirebreakCliPackage,
  mkLoopPackage,
  mkLoopSmokePackage,
  mkNpxLauncherSmokePackage,
  mkProjectConfigSmokePackage,
  mkRunnerPackage,
  mkSmokePackage,
  mkValidationFixturePackage,
  mkWorkspacePackage,
  mkWorkspaceSmokePackage,
  mkValidationPackage,
  mkValidationSmokePackage,
  mkWorkerFirebreakAttachSmokePackage,
  mkWorkerClaudeVersionSmokePackage,
  mkWorkerInteractiveClaudeDirectExitSmokePackage,
  mkWorkerInteractiveClaudeDirectSmokePackage,
  mkWorkerInteractiveCodexDirectSmokePackage,
  mkWorkerGuestBridgeInteractiveSmokePackage,
  mkWorkerGuestBridgeSmokePackage,
  mkWorkerPackage,
  mkWorkerProxyScriptSmokePackage,
  mkWorkerSmokePackage,
}:
let
  publicWorkloadManifest = builtins.fromJSON (builtins.readFile ../../share/public-workloads.json);
in
{
  default = self.packages.${system}.firebreak;

  firebreak-internal-runner-codex = localVmArtifacts.firebreak-codex.runnerPackage;
  firebreak-internal-runner-claude-code = localVmArtifacts.firebreak-claude-code.runnerPackage;
  firebreak-internal-runner-interactive-echo = localVmArtifacts.firebreak-interactive-echo.runnerPackage;

  firebreak-codex = localVmArtifacts.firebreak-codex.package;

  firebreak-test-smoke-codex = mkSmokePackage {
    name = "firebreak-test-smoke-codex";
    workloadPackage = "firebreak-codex";
    toolBin = "codex";
    toolDisplayName = "Codex";
    toolStateSubdir = "codex";
    defaultToolStateHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.codex";
  };

  firebreak-test-smoke-codex-version = mkWorkloadVersionSmokePackage {
    name = "firebreak-test-smoke-codex-version";
    workloadPackage = "firebreak-codex";
    toolDisplayName = "Codex";
  };

  firebreak-test-smoke-codex-warm-reuse = mkWorkloadWarmReuseSmokePackage {
    name = "firebreak-test-smoke-codex-warm-reuse";
    workloadPackage = "firebreak-codex";
    toolDisplayName = "Codex";
  };

  firebreak-claude-code = localVmArtifacts.firebreak-claude-code.package;

  firebreak-test-smoke-claude-code = mkSmokePackage {
    name = "firebreak-test-smoke-claude-code";
    workloadPackage = "firebreak-claude-code";
    toolBin = "claude";
    toolDisplayName = "Claude Code";
    toolStateSubdir = "claude";
    defaultToolStateHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.claude";
  };

  firebreak-interactive-echo = localVmArtifacts.firebreak-interactive-echo.package;
  firebreak-port-publish-fixture = localVmArtifacts.firebreak-port-publish-fixture.package;

  firebreak-credential-fixture = localVmArtifacts.firebreak-credential-fixture.package;

  firebreak-test-smoke-credential-slots = mkCredentialSlotSmokePackage {
    name = "firebreak-test-smoke-credential-slots";
    fixturePackage = "firebreak-credential-fixture";
  };

  firebreak-test-smoke-codex-credential-slots = mkToolCredentialSlotSmokePackage {
    name = "firebreak-test-smoke-codex-credential-slots";
    workloadPackage = "firebreak-codex";
    toolBin = "codex";
    toolDisplayName = "Codex";
    toolStateSubdir = "codex";
    authFile = "auth.json";
    authFileFormat = "json";
    apiKeyFile = "OPENAI_API_KEY";
    apiKeyEnv = "OPENAI_API_KEY";
    toolStateEnv = "CODEX_HOME";
    credentialSlotSpecificVar = "CODEX_CREDENTIAL_SLOT";
    loginCommand = "login";
    loginCommandArgs = [ "login" ];
  };

  firebreak-test-smoke-claude-code-credential-slots = mkToolCredentialSlotSmokePackage {
    name = "firebreak-test-smoke-claude-code-credential-slots";
    workloadPackage = "firebreak-claude-code";
    toolBin = "claude";
    toolDisplayName = "Claude Code";
    toolStateSubdir = "claude";
    authFile = ".credentials.json";
    authFileFormat = "json";
    apiKeyFile = "ANTHROPIC_API_KEY";
    apiKeyEnv = "ANTHROPIC_API_KEY";
    toolStateEnv = "CLAUDE_CONFIG_DIR";
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

  dev-flow-test-smoke-cli-surface = mkDevFlowCliSurfaceSmokePackage {
    name = "dev-flow-test-smoke-cli-surface";
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

  firebreak-test-smoke-cloud-hypervisor-egress-proxy = mkCloudHypervisorEgressProxySmokePackage {
    name = "firebreak-test-smoke-cloud-hypervisor-egress-proxy";
  };

  firebreak-test-smoke-cloud-hypervisor-port-publish = mkCloudHypervisorPortPublishSmokePackage {
    name = "firebreak-test-smoke-cloud-hypervisor-port-publish";
  };

  firebreak-test-smoke-port-publish-runtime = mkPortPublishRuntimeSmokePackage {
    name = "firebreak-test-smoke-port-publish-runtime";
    fixturePackage = "firebreak-port-publish-fixture";
  };

  firebreak-validation-fixture-pass = mkValidationFixturePackage {
    name = "firebreak-validation-fixture-pass";
    message = "validation fixture passed";
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

  firebreak-test-smoke-worker-claude-version = mkWorkerClaudeVersionSmokePackage {
    name = "firebreak-test-smoke-worker-claude-version";
    firebreakPackage = "firebreak";
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
    publicWorkloads = map
      (workload: workload // {
        launcher = "${self.packages.${system}.${workload.packageName}}/bin/${workload.packageName}";
      })
      publicWorkloadManifest;
  };

  dev-flow = mkDevFlowCliPackage {
    name = "dev-flow";
  };
} // lib.optionalAttrs (hostIsLinux && includeCloud) {
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
