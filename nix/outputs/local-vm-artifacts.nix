{ self, pkgs, mkLocalVmArtifacts }:
{
  firebreak-codex = mkLocalVmArtifacts {
    name = "firebreak-codex";
    extraModules = [ self.nixosModules.firebreak-codex ];
    controlSocketName = "firebreak-codex";
    defaultAgentCommand = "codex";
    agentConfigDirName = ".codex";
    defaultAgentConfigHostDir = "$HOME/.codex";
    agentEnvPrefix = "CODEX";
  };

  firebreak-claude-code = mkLocalVmArtifacts {
    name = "firebreak-claude-code";
    extraModules = [ self.nixosModules.firebreak-claude-code ];
    controlSocketName = "firebreak-claude-code";
    defaultAgentCommand = "claude";
    agentConfigDirName = ".claude";
    defaultAgentConfigHostDir = "$HOME/.claude";
    agentEnvPrefix = "CLAUDE";
  };

  firebreak-codex-cloud = mkLocalVmArtifacts {
    name = "firebreak-codex-cloud";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-codex ];
  };

  firebreak-claude-code-cloud = mkLocalVmArtifacts {
    name = "firebreak-claude-code-cloud";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-claude-code ];
  };

  firebreak-cloud-smoke = mkLocalVmArtifacts {
    name = "firebreak-cloud-smoke";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ {
      agentVm = {
        agentConfigEnabled = false;
        agentPromptCommand = ''
          case "$FIREBREAK_AGENT_PROMPT" in
            "Run the timeout validation fixture")
              ./timeout-fixture.sh
              ;;
            *)
              printf '%s\n' "$FIREBREAK_AGENT_PROMPT"
              ;;
          esac
        '';
        extraSystemPackages = with pkgs; [ coreutils ];
      };
    } ];
  };
}
