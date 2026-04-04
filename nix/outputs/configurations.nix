{ self, mkAgentVm, pkgs }:
{
  firebreak-codex = mkAgentVm {
    name = "firebreak-codex";
    extraModules = [ self.nixosModules.firebreak-codex ];
  };

  firebreak-claude-code = mkAgentVm {
    name = "firebreak-claude-code";
    extraModules = [ self.nixosModules.firebreak-claude-code ];
  };

  firebreak-credential-fixture = mkAgentVm {
    name = "firebreak-credential-fixture";
    extraModules = [ self.nixosModules.firebreak-credential-fixture ];
  };

  firebreak-interactive-echo = mkAgentVm {
    name = "firebreak-interactive-echo";
    extraModules = [ self.nixosModules.firebreak-interactive-echo ];
  };

  firebreak-codex-cloud = mkAgentVm {
    name = "firebreak-codex-cloud";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-codex ];
  };

  firebreak-claude-code-cloud = mkAgentVm {
    name = "firebreak-claude-code-cloud";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-claude-code ];
  };

  firebreak-cloud-smoke = mkAgentVm {
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
