{
  description = "Skada Firebreak: reliable isolation for high-trust automation";

  inputs.nixpkgs.url = "nixpkgs";
  inputs.microvm = {
    url = "github:microvm-nix/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, microvm }:
    let
      lib = nixpkgs.lib;
      supportedHostSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      defaultHostSystem = "x86_64-linux";
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
      recipeLib = {
        inherit (supports.${defaultHostSystem})
          mkPackagedNodeCliFlakeOutputs
          ;
      };

      lib = lib.genAttrs supportedHostSystems (system: {
        inherit (supports.${system})
          mkWorkloadVm
          mkLocalVmArtifacts
          mkLocalVmPackage
          mkPackagedNodeCliArtifacts
          mkPackagedNodeCliFlakeOutputs
          mkRunnerPackage
          mkWorkerProxyScript
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
            mkWorkloadPackage
            mkWorkloadVersionSmokePackage
            mkCloudJobPackage
            mkCloudSmokePackage
            mkDevFlowCliPackage
            mkDevFlowCliSurfaceSmokePackage
            mkCredentialSlotSmokePackage
            mkToolCredentialSlotSmokePackage
            mkFirebreakCliSurfaceSmokePackage
            mkWorkerFirebreakBridgeProbePackage
            mkFirebreakCliPackage
            mkLoopPackage
            mkLoopSmokePackage
            mkNpxLauncherSmokePackage
            mkProjectConfigSmokePackage
            mkRunnerPackage
            mkSmokePackage
            mkWorkspacePackage
            mkWorkspaceSmokePackage
            mkValidationPackage
            mkValidationSmokePackage
            mkWorkerFirebreakAttachSmokePackage
            mkWorkerInteractiveClaudeDirectExitSmokePackage
            mkWorkerInteractiveClaudeDirectSmokePackage
            mkWorkerInteractiveCodexDirectSmokePackage
            mkWorkerGuestBridgeInteractiveSmokePackage
            mkWorkerGuestBridgeSmokePackage
            mkWorkerPackage
            mkWorkerProxyScriptSmokePackage
            mkWorkerSmokePackage
            ;
        });

      apps = lib.genAttrs supportedHostSystems (system: {
        default = self.apps.${system}.firebreak;

        firebreak = {
          type = "app";
          program = "${self.packages.${system}.firebreak}/bin/firebreak";
        };
      });

      checks = lib.genAttrs supportedHostSystems (system:
        import ./nix/outputs/checks.nix {
          inherit self system;
          localVmArtifacts = localVmArtifacts.${system};
          inherit (supports.${system}) hostIsLinux lib;
        });
    };
}
