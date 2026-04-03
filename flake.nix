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
      defaultHostSystem = "x86_64-linux";
      supportedHostSystems = [
        defaultHostSystem
        "aarch64-linux"
        "aarch64-darwin"
      ];
      guestSystemFor = hostSystem:
        if hostSystem == "aarch64-darwin" then
          "aarch64-linux"
        else
          hostSystem;
      supports = lib.genAttrs supportedHostSystems (system:
        import ./nix/flake-support.nix {
          inherit self nixpkgs microvm system;
          guestSystem = guestSystemFor system;
        });
      localVmArtifacts = lib.genAttrs supportedHostSystems (system:
        import ./nix/outputs/local-vm-artifacts.nix {
          inherit self;
          includeCloud = supports.${system}.hostIsLinux;
          inherit (supports.${system}) mkLocalVmArtifacts pkgs;
        });
    in {
      lib = lib.genAttrs supportedHostSystems (system: {
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

      nixosConfigurations = lib.mapAttrs (_: artifacts: artifacts.nixosConfiguration) localVmArtifacts.${defaultHostSystem};

      packages = lib.genAttrs supportedHostSystems (system:
        import ./nix/outputs/packages.nix {
          inherit self system;
          localVmArtifacts = localVmArtifacts.${system};
          inherit (supports.${system})
            hostIsLinux
            lib
            mkAgentVersionSmokePackage
            mkCloudJobPackage
            mkCloudSmokePackage
            mkDevFlowCliPackage
            mkDevFlowCliSurfaceSmokePackage
            mkFirebreakCliSurfaceSmokePackage
            mkFirebreakCliPackage
            mkLoopPackage
            mkLoopSmokePackage
            mkNpxLauncherSmokePackage
            mkProjectConfigSmokePackage
            mkSmokePackage
            mkWorkspacePackage
            mkWorkspaceSmokePackage
            mkValidationPackage
            mkValidationSmokePackage
            ;
        });

      checks = lib.genAttrs supportedHostSystems (system:
        import ./nix/outputs/checks.nix {
          inherit self system;
          localVmArtifacts = localVmArtifacts.${system};
          inherit (supports.${system}) hostIsLinux lib;
        });
    };
}
