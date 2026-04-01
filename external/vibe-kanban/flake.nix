{
  description = "Firebreak sandbox recipe for BloopAI/vibe-kanban";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.firebreak.url = "github:skadaai/firebreak";
  inputs.firebreak.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { firebreak, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mkProject = forwardPorts:
        firebreak.lib.${system}.mkPackagedNodeCliArtifacts {
          name = "firebreak-vibe-kanban";
          displayName = "Vibe Kanban";
          tagline = "vibe-kanban cli sandbox";
          packageSpec = "vibe-kanban";
          binName = "vibe-kanban";
          workerProxies = {
            codex = {
              kind = "codex";
              backend = "firebreak";
              package = "firebreak-codex";
              vm_mode = "run";
              max_instances = 4;
              versionOutput = "codex firebreak-worker wrapper";
            };
            claude = {
              kind = "claude-code";
              backend = "firebreak";
              package = "firebreak-claude-code";
              vm_mode = "run";
              max_instances = 2;
              versionOutput = "claude firebreak-worker wrapper";
            };
          };
          runtimePackages = pkgs: with pkgs; [
            git
          ];
          launchEnvironment = {
            FRONTEND_PORT = "3000";
            BACKEND_PORT = "3001";
            HOST = "0.0.0.0";
          };
          inherit forwardPorts;
          launchCommand = "vibe-kanban";
          extraShellInit = ''
            alias vk-dev='project-launch'
          '';
        };
      project = mkProject [
        {
          from = "host";
          proto = "tcp";
          host.address = "127.0.0.1";
          host.port = 3000;
          guest.port = 3000;
        }
        {
          from = "host";
          proto = "tcp";
          host.address = "127.0.0.1";
          host.port = 3001;
          guest.port = 3001;
        }
      ];
      testProject = mkProject [ ];
      tests = import ./tests.nix {
        inherit pkgs project testProject;
        firebreakBin = "${firebreak.packages.${system}.default}/bin/firebreak";
      };
    in {
      nixosConfigurations.firebreak-vibe-kanban = project.nixosConfiguration;

      packages.${system} = {
        default = project.package;
        firebreak-vibe-kanban = project.package;
        firebreak-internal-runner-vibe-kanban = project.runnerPackage;
      } // tests.packages;

      checks.${system} = tests.checks;
    };
}
