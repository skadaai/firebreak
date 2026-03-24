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
