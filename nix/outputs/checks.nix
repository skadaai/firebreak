{
  self,
  system,
  hostIsLinux,
  lib,
  localVmArtifacts,
}:
{
  firebreak-internal-runner-codex = self.packages.${system}.firebreak-internal-runner-codex;
  firebreak-codex-system = localVmArtifacts.firebreak-codex.nixosConfiguration.config.system.build.toplevel;
  dev-flow-test-smoke-cli-surface = self.packages.${system}.dev-flow-test-smoke-cli-surface;
  dev-flow-test-smoke-loop = self.packages.${system}.dev-flow-test-smoke-loop;
  dev-flow-test-smoke-validate = self.packages.${system}.dev-flow-test-smoke-validate;
  dev-flow-test-smoke-workspace = self.packages.${system}.dev-flow-test-smoke-workspace;
  firebreak-test-smoke-codex = self.packages.${system}.firebreak-test-smoke-codex;
  firebreak-internal-runner-interactive-echo = self.packages.${system}.firebreak-internal-runner-interactive-echo;
  firebreak-interactive-echo-system = localVmArtifacts.firebreak-interactive-echo.nixosConfiguration.config.system.build.toplevel;
  firebreak-test-smoke-firebreak-cli-surface = self.packages.${system}.firebreak-test-smoke-firebreak-cli-surface;
  firebreak-test-smoke-worker-proxy-script = self.packages.${system}.firebreak-test-smoke-worker-proxy-script;
  firebreak-test-smoke-npx-launcher = self.packages.${system}.firebreak-test-smoke-npx-launcher;
  firebreak-test-smoke-project-config-and-doctor = self.packages.${system}.firebreak-test-smoke-project-config-and-doctor;
  firebreak-test-smoke-worker = self.packages.${system}.firebreak-test-smoke-worker;
  firebreak-test-smoke-worker-firebreak-attach = self.packages.${system}.firebreak-test-smoke-worker-firebreak-attach;
  firebreak-test-smoke-worker-interactive-claude-direct = self.packages.${system}.firebreak-test-smoke-worker-interactive-claude-direct;
  firebreak-test-smoke-worker-interactive-claude-exit-direct = self.packages.${system}.firebreak-test-smoke-worker-interactive-claude-exit-direct;
  firebreak-test-smoke-worker-interactive-codex-direct = self.packages.${system}.firebreak-test-smoke-worker-interactive-codex-direct;
  firebreak-test-smoke-worker-guest-bridge = self.packages.${system}.firebreak-test-smoke-worker-guest-bridge;
  firebreak-test-smoke-worker-guest-bridge-interactive = self.packages.${system}.firebreak-test-smoke-worker-guest-bridge-interactive;
  firebreak-internal-runner-claude-code = self.packages.${system}.firebreak-internal-runner-claude-code;
  firebreak-claude-code-system = localVmArtifacts.firebreak-claude-code.nixosConfiguration.config.system.build.toplevel;
  firebreak-test-smoke-claude-code = self.packages.${system}.firebreak-test-smoke-claude-code;
  firebreak-credential-fixture-system = localVmArtifacts.firebreak-credential-fixture.nixosConfiguration.config.system.build.toplevel;
  firebreak-test-smoke-credential-slots = self.packages.${system}.firebreak-test-smoke-credential-slots;
  firebreak-test-smoke-codex-credential-slots = self.packages.${system}.firebreak-test-smoke-codex-credential-slots;
  firebreak-test-smoke-claude-code-credential-slots = self.packages.${system}.firebreak-test-smoke-claude-code-credential-slots;
} // lib.optionalAttrs hostIsLinux {
  firebreak-internal-runner-codex-cloud = self.packages.${system}.firebreak-internal-runner-codex-cloud;
  firebreak-codex-cloud-system = localVmArtifacts.firebreak-codex-cloud.nixosConfiguration.config.system.build.toplevel;
  firebreak-test-smoke-cloud-job = self.packages.${system}.firebreak-test-smoke-cloud-job;
  firebreak-internal-runner-claude-code-cloud = self.packages.${system}.firebreak-internal-runner-claude-code-cloud;
  firebreak-claude-code-cloud-system = localVmArtifacts.firebreak-claude-code-cloud.nixosConfiguration.config.system.build.toplevel;
  firebreak-internal-runner-test-cloud = self.packages.${system}.firebreak-internal-runner-test-cloud;
  firebreak-test-smoke-cloud-system = localVmArtifacts.firebreak-cloud-smoke.nixosConfiguration.config.system.build.toplevel;
}
