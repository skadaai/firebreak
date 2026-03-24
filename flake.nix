{
  description = "Skada Firebreak: reliable isolation for high-trust automation";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs.nixpkgs.url = "nixpkgs";
  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      lib = nixpkgs.lib;
      defaultSystem = "x86_64-linux";
      supportedSystems = [
        defaultSystem
        "aarch64-linux"
      ];
      supports = lib.genAttrs supportedSystems (system:
        import ./nix/flake-support.nix {
          inherit self nixpkgs microvm system;
        });
      localVmArtifacts = lib.genAttrs supportedSystems (system:
        import ./nix/outputs/local-vm-artifacts.nix {
          inherit self;
          inherit (supports.${system}) mkLocalVmArtifacts pkgs;
        });
    in {
      lib = lib.genAttrs supportedSystems (system: {
        inherit (supports.${system})
          mkAgentVm
          mkLocalVmArtifacts
          mkLocalVmPackage
          mkPackagedNodeCliArtifacts
          mkRunnerPackage
          mkWorkspaceProjectArtifacts
          ;
      });

      nixosModules = import ./nix/outputs/modules.nix {
        inherit self;
      };

      nixosConfigurations = lib.mapAttrs (_: artifacts: artifacts.nixosConfiguration) localVmArtifacts.${defaultSystem};

      packages = lib.genAttrs supportedSystems (system:
        import ./nix/outputs/packages.nix {
          inherit self system;
          localVmArtifacts = localVmArtifacts.${system};
          inherit (supports.${system})
            mkAgentVersionSmokePackage
            mkCloudJobPackage
            mkCloudSmokePackage
            mkFirebreakCliSurfaceSmokePackage
            mkFirebreakCliPackage
            mkLoopPackage
            mkLoopSmokePackage
            mkNpxLauncherSmokePackage
            mkProjectConfigSmokePackage
            mkSmokePackage
            mkTaskPackage
            mkTaskSmokePackage
            mkValidationPackage
            mkValidationSmokePackage
            ;
        });

      checks = lib.genAttrs supportedSystems (system:
        import ./nix/outputs/checks.nix {
          inherit self system;
          localVmArtifacts = localVmArtifacts.${system};
        });
    };
}
