{ self }:
{
  firebreak-vm-base = import ../../modules/base/module.nix;
  firebreak-local-profile = import ../../modules/profiles/local/module.nix;
  firebreak-cloud-profile = import ../../modules/profiles/cloud/module.nix;
  agent-vm-base = {
    imports = [
      self.nixosModules.firebreak-vm-base
      self.nixosModules.firebreak-local-profile
    ];
  };
  firebreak-codex = import ../../modules/codex/module.nix;
  firebreak-claude-code = import ../../modules/claude-code/module.nix;
  default = self.nixosModules.firebreak-codex;
}
