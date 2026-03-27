{ self, system }:
{
  firebreak-internal-runner-codex = self.packages.${system}.firebreak-internal-runner-codex;
  firebreak-codex-system = self.nixosConfigurations.firebreak-codex.config.system.build.toplevel;
  firebreak-test-smoke-codex = self.packages.${system}.firebreak-test-smoke-codex;
  firebreak-internal-runner-interactive-echo = self.packages.${system}.firebreak-internal-runner-interactive-echo;
  firebreak-interactive-echo-system = self.nixosConfigurations.firebreak-interactive-echo.config.system.build.toplevel;
  firebreak-internal-runner-codex-cloud = self.packages.${system}.firebreak-internal-runner-codex-cloud;
  firebreak-codex-cloud-system = self.nixosConfigurations.firebreak-codex-cloud.config.system.build.toplevel;
  firebreak-test-smoke-cloud-job = self.packages.${system}.firebreak-test-smoke-cloud-job;
  firebreak-test-smoke-firebreak-cli-surface = self.packages.${system}.firebreak-test-smoke-firebreak-cli-surface;
  firebreak-test-smoke-npx-launcher = self.packages.${system}.firebreak-test-smoke-npx-launcher;
  firebreak-test-smoke-project-config-and-doctor = self.packages.${system}.firebreak-test-smoke-project-config-and-doctor;
  firebreak-test-smoke-internal-loop = self.packages.${system}.firebreak-test-smoke-internal-loop;
  firebreak-test-smoke-internal-task = self.packages.${system}.firebreak-test-smoke-internal-task;
  firebreak-test-smoke-internal-validate = self.packages.${system}.firebreak-test-smoke-internal-validate;
  firebreak-test-smoke-worker = self.packages.${system}.firebreak-test-smoke-worker;
  firebreak-test-smoke-worker-firebreak-attach = self.packages.${system}.firebreak-test-smoke-worker-firebreak-attach;
  firebreak-test-smoke-worker-guest-bridge = self.packages.${system}.firebreak-test-smoke-worker-guest-bridge;
  firebreak-test-smoke-worker-guest-bridge-interactive = self.packages.${system}.firebreak-test-smoke-worker-guest-bridge-interactive;
  firebreak-internal-runner-claude-code = self.packages.${system}.firebreak-internal-runner-claude-code;
  firebreak-claude-code-system = self.nixosConfigurations.firebreak-claude-code.config.system.build.toplevel;
  firebreak-test-smoke-claude-code = self.packages.${system}.firebreak-test-smoke-claude-code;
  firebreak-internal-runner-claude-code-cloud = self.packages.${system}.firebreak-internal-runner-claude-code-cloud;
  firebreak-claude-code-cloud-system = self.nixosConfigurations.firebreak-claude-code-cloud.config.system.build.toplevel;
  firebreak-internal-runner-test-cloud = self.packages.${system}.firebreak-internal-runner-test-cloud;
  firebreak-test-smoke-cloud-system = self.nixosConfigurations.firebreak-cloud-smoke.config.system.build.toplevel;
}
