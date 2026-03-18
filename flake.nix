{
  description = "NixOS in MicroVMs";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      renderTemplate = vars: path:
        lib.replaceStrings
          (builtins.attrNames vars)
          (builtins.attrValues vars)
          (builtins.readFile path);
    in {
      nixosModules.default = import ./nix/codex-vm.nix;

      packages.${system} = {
        default = self.packages.${system}.codex-vm;
        codex-vm-runner = self.nixosConfigurations.codex-vm.config.microvm.declaredRunner;
        codex-vm = pkgs.writeShellApplication {
          name = "codex-vm";
          runtimeInputs = with pkgs; [ coreutils ];
          text = renderTemplate {
            "@RUNNER@" = "${self.packages.${system}.codex-vm-runner}/bin/microvm-run";
          } ./scripts/run-wrapper.sh;
        };
      };

      nixosConfigurations.codex-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit renderTemplate;
        };
        modules = [
          microvm.nixosModules.microvm
          self.nixosModules.default
        ];
      };

      checks.${system} = {
        codex-vm-runner = self.packages.${system}.codex-vm-runner;
        codex-vm-system = self.nixosConfigurations.codex-vm.config.system.build.toplevel;
      };
    };
}
