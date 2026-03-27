{ lib, pkgs, ... }:
let
  interactiveEcho = pkgs.writeShellApplication {
    name = "interactive-echo";
    runtimeInputs = with pkgs; [
      bash
      coreutils
    ];
    text = ''
      set -eu
      printf 'READY\n'
      IFS= read -r line
      printf 'ECHO:%s\n' "$line"
    '';
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault "firebreak-interactive-echo";
      agentConfigEnabled = false;
      agentCommand = "interactive-echo";
      extraSystemPackages = [ interactiveEcho ];
      bootstrapScript = null;
    };

    networking.firewall.enable = false;
  };
}
