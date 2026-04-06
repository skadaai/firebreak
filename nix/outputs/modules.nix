{ self }:
{
  firebreak-vm-base = import ../../modules/base/module.nix;
  firebreak-local-profile = import ../../modules/profiles/local/module.nix;
  firebreak-cloud-profile = import ../../modules/profiles/cloud/module.nix;
  workload-vm-base = {
    imports = [
      self.nixosModules.firebreak-vm-base
      self.nixosModules.firebreak-local-profile
    ];
  };
  firebreak-codex = import ../../modules/codex/module.nix;
  firebreak-claude-code = import ../../modules/claude-code/module.nix;
  firebreak-credential-fixture = import ../../modules/credential-fixture/module.nix;
  firebreak-interactive-echo = import ../../modules/interactive-echo/module.nix;
  firebreak-port-publish-fixture = import ../../modules/port-publish-fixture/module.nix;
  default = self.nixosModules.firebreak-codex;
}
