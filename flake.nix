{
  description = "Skada Firebreak: reliable isolation for high-trust automation";

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
      support = import ./nix/flake-support.nix {
        inherit self nixpkgs microvm system;
      };
    in {
      nixosModules = import ./nix/outputs/modules.nix {
        inherit self;
      };

      nixosConfigurations = import ./nix/outputs/configurations.nix {
        inherit self;
        inherit (support) mkAgentVm pkgs;
      };

      packages.${system} = import ./nix/outputs/packages.nix {
        inherit self system;
        inherit (support)
          mkAgentPackage
          mkAgentVersionSmokePackage
          mkCloudJobPackage
          mkCloudSmokePackage
          mkFirebreakCliPackage
          mkLoopPackage
          mkLoopSmokePackage
          mkNpxLauncherSmokePackage
          mkProjectConfigSmokePackage
          mkRunnerPackage
          mkSmokePackage
          mkTaskPackage
          mkTaskSmokePackage
          mkValidationPackage
          mkValidationSmokePackage
          ;
      };

      checks.${system} = import ./nix/outputs/checks.nix {
        inherit self system;
      };
    };
}
