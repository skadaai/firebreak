{ self, pkgs, mkLocalVmArtifacts, includeCloud ? true }:
let
  inherit (pkgs) lib;
in
{
  firebreak-codex = mkLocalVmArtifacts {
    name = "firebreak-codex";
    extraModules = [ self.nixosModules.firebreak-codex ];
    controlSocketName = "firebreak-codex";
    defaultToolCommand = "codex";
    toolStateSubdir = "codex";
    defaultToolStateHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.codex";
    hostConfigAdoptionEnabled = true;
    toolEnvPrefix = "CODEX";
    sharedStateRoots.enable = true;
    sharedCredentialSlots.enable = true;
  };

  firebreak-claude-code = mkLocalVmArtifacts {
    name = "firebreak-claude-code";
    extraModules = [ self.nixosModules.firebreak-claude-code ];
    controlSocketName = "firebreak-claude-code";
    defaultToolCommand = "claude";
    toolStateSubdir = "claude";
    defaultToolStateHostDir = "$HOME/.firebreak";
    workspaceBootstrapConfigHostDir = "$HOME/.claude";
    hostConfigAdoptionEnabled = true;
    toolEnvPrefix = "CLAUDE";
    sharedStateRoots.enable = true;
    sharedCredentialSlots.enable = true;
  };

  firebreak-credential-fixture = mkLocalVmArtifacts {
    name = "firebreak-credential-fixture";
    extraModules = [ self.nixosModules.firebreak-credential-fixture ];
    controlSocketName = "firebreak-credential-fixture";
    defaultToolCommand = "credential-fixture";
    toolStateSubdir = "credential-fixture";
    defaultToolStateHostDir = "$HOME/.firebreak";
    toolEnvPrefix = "FIXTURE";
    sharedStateRoots.enable = true;
    sharedCredentialSlots.enable = true;
  };

  firebreak-interactive-echo = mkLocalVmArtifacts {
    name = "firebreak-interactive-echo";
    extraModules = [ self.nixosModules.firebreak-interactive-echo ];
    controlSocketName = "firebreak-interactive-echo";
    defaultToolCommand = "interactive-echo";
    toolStateSubdir = "interactive-echo";
    defaultToolStateHostDir = "$HOME/.firebreak";
  };

  firebreak-port-publish-fixture = mkLocalVmArtifacts {
    name = "firebreak-port-publish-fixture";
    extraModules = [ self.nixosModules.firebreak-port-publish-fixture ];
    controlSocketName = "firebreak-port-publish-fixture";
    defaultToolCommand = "bash";
    toolStateSubdir = "port-publish-fixture";
    defaultToolStateHostDir = "$HOME/.firebreak";
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
          case "$FIREBREAK_TOOL_PROMPT" in
            "Run the timeout validation fixture")
              ./timeout-fixture.sh
              ;;
            *)
              printf '%s\n' "$FIREBREAK_TOOL_PROMPT"
              ;;
          esac
        '';
        extraSystemPackages = with pkgs; [ coreutils ];
      };
    } ];
  };
}
