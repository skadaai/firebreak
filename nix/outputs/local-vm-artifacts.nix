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
    sharedStateRoots.enable = true;
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
    sharedStateRoots.enable = true;
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
    sharedStateRoots.enable = true;
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

  firebreak-port-publish-fixture = mkLocalVmArtifacts {
    name = "firebreak-port-publish-fixture";
    extraModules = [ self.nixosModules.firebreak-port-publish-fixture ];
    controlSocketName = "firebreak-port-publish-fixture";
    defaultAgentCommand = "bash";
    agentConfigSubdir = "port-publish-fixture";
    defaultAgentConfigHostDir = "$HOME/.firebreak";
  };

} // lib.optionalAttrs includeCloud {
  firebreak-codex-cloud = mkLocalVmArtifacts {
    name = "firebreak-codex-cloud";
    runtimeBackend = "qemu";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-codex ];
  };

  firebreak-claude-code-cloud = mkLocalVmArtifacts {
    name = "firebreak-claude-code-cloud";
    runtimeBackend = "qemu";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-claude-code ];
  };

  firebreak-cloud-smoke = mkLocalVmArtifacts {
    name = "firebreak-cloud-smoke";
    runtimeBackend = "qemu";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ {
      workloadVm = {
        promptCommand = ''
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
