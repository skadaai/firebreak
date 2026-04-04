{ self, pkgs, mkLocalVmArtifacts, includeCloud ? true }:
let
  inherit (pkgs) lib;
in
{
  firebreak-codex = mkLocalVmArtifacts {
    name = "firebreak-codex";
    extraModules = [ self.nixosModules.firebreak-codex ];
    controlSocketName = "firebreak-codex";
    defaultAgentCommand = "codex";
    agentConfigSubdir = "codex";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.codex";
    hostConfigAdoptionEnabled = true;
    agentEnvPrefix = "CODEX";
    sharedAgentConfig.enable = true;
    sharedCredentialSlots.enable = true;
  };

  firebreak-claude-code = mkLocalVmArtifacts {
    name = "firebreak-claude-code";
    extraModules = [ self.nixosModules.firebreak-claude-code ];
    controlSocketName = "firebreak-claude-code";
    defaultAgentCommand = "claude";
    agentConfigSubdir = "claude";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.claude";
    hostConfigAdoptionEnabled = true;
    agentEnvPrefix = "CLAUDE";
    sharedAgentConfig.enable = true;
    sharedCredentialSlots.enable = true;
  };

  firebreak-credential-fixture = mkLocalVmArtifacts {
    name = "firebreak-credential-fixture";
    extraModules = [ self.nixosModules.firebreak-credential-fixture ];
    controlSocketName = "firebreak-credential-fixture";
    defaultAgentCommand = "credential-fixture";
    agentConfigSubdir = "credential-fixture";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
    agentEnvPrefix = "FIXTURE";
    sharedAgentConfig.enable = true;
    sharedCredentialSlots.enable = true;
  };

  firebreak-interactive-echo = mkLocalVmArtifacts {
    name = "firebreak-interactive-echo";
    extraModules = [ self.nixosModules.firebreak-interactive-echo ];
    controlSocketName = "firebreak-interactive-echo";
    defaultAgentCommand = "interactive-echo";
    agentConfigSubdir = "interactive-echo";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
  };

} // lib.optionalAttrs includeCloud {
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
