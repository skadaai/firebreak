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
  firebreak-test-smoke-firebreak-cli-surface = self.packages.${system}.firebreak-test-smoke-firebreak-cli-surface;
  firebreak-test-smoke-npx-launcher = self.packages.${system}.firebreak-test-smoke-npx-launcher;
  firebreak-test-smoke-project-config-and-doctor = self.packages.${system}.firebreak-test-smoke-project-config-and-doctor;
  firebreak-internal-runner-claude-code = self.packages.${system}.firebreak-internal-runner-claude-code;
  firebreak-claude-code-system = localVmArtifacts.firebreak-claude-code.nixosConfiguration.config.system.build.toplevel;
  firebreak-test-smoke-claude-code = self.packages.${system}.firebreak-test-smoke-claude-code;
} // lib.optionalAttrs hostIsLinux {
  firebreak-internal-runner-codex-cloud = self.packages.${system}.firebreak-internal-runner-codex-cloud;
  firebreak-codex-cloud-system = localVmArtifacts.firebreak-codex-cloud.nixosConfiguration.config.system.build.toplevel;
  firebreak-test-smoke-cloud-job = self.packages.${system}.firebreak-test-smoke-cloud-job;
  firebreak-internal-runner-claude-code-cloud = self.packages.${system}.firebreak-internal-runner-claude-code-cloud;
  firebreak-claude-code-cloud-system = localVmArtifacts.firebreak-claude-code-cloud.nixosConfiguration.config.system.build.toplevel;
  firebreak-internal-runner-test-cloud = self.packages.${system}.firebreak-internal-runner-test-cloud;
  firebreak-test-smoke-cloud-system = localVmArtifacts.firebreak-cloud-smoke.nixosConfiguration.config.system.build.toplevel;
}
