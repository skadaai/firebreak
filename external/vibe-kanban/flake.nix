{
  description = "Firebreak sandbox recipe for BloopAI/vibe-kanban";

  inputs.firebreak.url = "github:skadaai/firebreak";

  outputs = { firebreak, ... }:
    let
      system = "x86_64-linux";
      project = firebreak.lib.${system}.mkPackagedNodeCliArtifacts {
        name = "firebreak-vibe-kanban";
        displayName = "Vibe Kanban";
        tagline = "vibe-kanban cli sandbox";
        packageSpec = "vibe-kanban";
        binName = "vibe-kanban";
        workerBridgeEnabled = true;
        workerKinds = {
          codex = {
            backend = "firebreak";
            package = "firebreak-codex";
            vm_mode = "run";
            max_instances = 4;
          };
          claude-code = {
            backend = "firebreak";
            package = "firebreak-claude-code";
            vm_mode = "run";
            max_instances = 2;
          };
        };
        runtimePackages = pkgs: with pkgs; [
          git
        ];
        installBinScripts = {
          codex = firebreak.lib.${system}.mkWorkerProxyScript {
            kind = "codex";
            versionOutput = "codex firebreak-worker wrapper";
          };
          claude = firebreak.lib.${system}.mkWorkerProxyScript {
            kind = "claude-code";
            versionOutput = "claude firebreak-worker wrapper";
          };
        };
        launchEnvironment = {
          FRONTEND_PORT = "3000";
          BACKEND_PORT = "3001";
          HOST = "0.0.0.0";
        };
        forwardPorts = [
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
        launchCommand = "vibe-kanban";
        extraShellInit = ''
          alias vk-dev='project-launch'
        '';
      };
    in {
      nixosConfigurations.firebreak-vibe-kanban = project.nixosConfiguration;

      packages.${system} = {
        default = project.package;
        firebreak-vibe-kanban = project.package;
        firebreak-internal-runner-vibe-kanban = project.runnerPackage;
      };
    };
}
