{
  description = "Firebreak sandbox recipe for BloopAI/vibe-kanban";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.firebreak.url = "github:skadaai/firebreak";
  inputs.firebreak.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { firebreak, nixpkgs, ... }:
    let
      mkProject = system: forwardPorts:
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
    in
    firebreak.recipeLib.mkPackagedNodeCliFlakeOutputs {
      inherit firebreak nixpkgs mkProject;
      testsModule = ./tests.nix;
      nixosConfigurationName = "firebreak-vibe-kanban";
      packageName = "firebreak-vibe-kanban";
      runnerPackageName = "firebreak-internal-runner-vibe-kanban";
      defaultForwardPorts = [
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
    };
}
