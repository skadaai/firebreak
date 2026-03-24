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
        runtimePackages = pkgs: with pkgs; [
          git
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
