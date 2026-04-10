{ lib, pkgs, ... }:
let
  interactiveEcho = pkgs.writeShellApplication {
    name = "interactive-echo";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = ''
      set -eu
      state_path=/run/firebreak-worker/interactive-echo.log
      if [ -d /run/command-exec-output ]; then
        state_path=/run/command-exec-output/interactive-echo.log
      fi
      mkdir -p "$(dirname "$state_path")"
      printf '%s\n' 'cursor-query-start' >>"$state_path"
      printf '\033[6n'
      cursor_reply=""
      if IFS= read -r -d R -t 2 cursor_reply; then
        cursor_reply="''${cursor_reply}R"
      fi
      cursor_reply_hex=$(printf '%s' "$cursor_reply" | od -An -tx1 | tr -d ' \n')
      printf '%s\n' "cursor-reply-hex:''${cursor_reply_hex:-missing}" >>"$state_path"
      printf '%s\n' 'ready-write-start' >>"$state_path"
      printf 'READY\n'
      printf '%s\n' 'ready-write-done' >>"$state_path"
      printf '%s\n' 'read-start' >>"$state_path"
      IFS= read -r line
      printf '%s\n' "read-done:$line" >>"$state_path"
      printf 'ECHO:%s\n' "$line"
      printf '%s\n' 'echo-write-done' >>"$state_path"
    '';
  };
in {
  config = {
    workloadVm = {
      name = lib.mkDefault "firebreak-interactive-echo";
      defaultCommand = "interactive-echo";
      extraSystemPackages = [ interactiveEcho ];
      bootstrapScript = null;
    };

    networking.firewall.enable = false;
  };
}
