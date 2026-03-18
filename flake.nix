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
      packages.${system} = {
        default = self.packages.${system}.my-microvm;
        my-microvm-runner = self.nixosConfigurations.my-microvm.config.microvm.declaredRunner;
        my-microvm = pkgs.writeShellApplication {
          name = "my-microvm";
          runtimeInputs = with pkgs; [ coreutils ];
          text = renderTemplate {
            "@RUNNER@" = "${self.packages.${system}.my-microvm-runner}/bin/microvm-run";
          } ./scripts/my-microvm-wrapper.sh;
        };
      };

      nixosConfigurations.my-microvm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          (import ./nix/my-microvm.nix {
            inherit lib pkgs renderTemplate;
          })
        ];
      };

      checks.${system} = {
        my-microvm-runner = self.packages.${system}.my-microvm-runner;
        my-microvm-system = self.nixosConfigurations.my-microvm.config.system.build.toplevel;
      };
    };
}
