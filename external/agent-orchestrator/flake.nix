{
  description = "Firebreak sandbox recipe for ComposioHQ/agent-orchestrator";

  inputs.firebreak.url = "github:skadaai/firebreak";

  outputs = { firebreak, ... }:
    let
      system = "x86_64-linux";
      project = firebreak.lib.${system}.mkPackagedNodeCliArtifacts {
        name = "firebreak-agent-orchestrator";
        displayName = "Agent Orchestrator";
        tagline = "agent-orchestrator cli sandbox";
        packageSpec = "@composio/ao";
        binName = "ao";
        runtimePackages = pkgs: with pkgs; [
          git
          gh
          tmux
        ];
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
            host.port = 14800;
            guest.port = 14800;
          }
          {
            from = "host";
            proto = "tcp";
            host.address = "127.0.0.1";
            host.port = 14801;
            guest.port = 14801;
          }
        ];
        launchCommand = "ao start .";
        extraShellInit = ''
          alias ao-start='project-launch'
        '';
      };
    in {
      nixosConfigurations.firebreak-agent-orchestrator = project.nixosConfiguration;

      packages.${system} = {
        default = project.package;
        firebreak-agent-orchestrator = project.package;
        firebreak-internal-runner-agent-orchestrator = project.runnerPackage;
      };
    };
}
