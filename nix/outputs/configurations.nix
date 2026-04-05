{ self, mkWorkloadVm, pkgs }:
{
  firebreak-codex = mkWorkloadVm {
    name = "firebreak-codex";
    extraModules = [ self.nixosModules.firebreak-codex ];
  };

  firebreak-claude-code = mkWorkloadVm {
    name = "firebreak-claude-code";
    extraModules = [ self.nixosModules.firebreak-claude-code ];
  };

  firebreak-credential-fixture = mkWorkloadVm {
    name = "firebreak-credential-fixture";
    extraModules = [ self.nixosModules.firebreak-credential-fixture ];
  };

  firebreak-interactive-echo = mkWorkloadVm {
    name = "firebreak-interactive-echo";
    extraModules = [ self.nixosModules.firebreak-interactive-echo ];
  };

  firebreak-codex-cloud = mkWorkloadVm {
    name = "firebreak-codex-cloud";
    runtimeBackend = "qemu";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-codex ];
  };

  firebreak-claude-code-cloud = mkWorkloadVm {
    name = "firebreak-claude-code-cloud";
    runtimeBackend = "qemu";
    profileModules = [ self.nixosModules.firebreak-cloud-profile ];
    extraModules = [ self.nixosModules.firebreak-claude-code ];
  };

  firebreak-cloud-smoke = mkWorkloadVm {
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
