{ lib, pkgs, ... }:
let
  guestPort = 48123;
  hostPort = 39123;
  webRoot = pkgs.writeTextDir "index.html" ''
    rootless publish ok
  '';
  portPublishFixtureServer = pkgs.writeShellApplication {
    name = "port-publish-fixture-server";
    runtimeInputs = with pkgs; [ python3 ];
    text = ''
      set -eu
      exec python3 -m http.server ${toString guestPort} --bind 127.0.0.1 --directory ${webRoot}
    '';
  };
in {
  config = {
    workloadVm = {
      name = lib.mkDefault "firebreak-port-publish-fixture";
      defaultCommand = "bash";
      requiredCapabilities = [ "host-port-publish-tcp" ];
      localPublishedHostPortsJson = builtins.toJSON [
        {
          from = "host";
          proto = "tcp";
          host = {
            address = "127.0.0.1";
            port = hostPort;
          };
          guest = {
            address = "127.0.0.1";
            port = guestPort;
          };
        }
      ];
      extraSystemPackages = [ portPublishFixtureServer ];
      bootstrapScript = null;
    };

    systemd.services.port-publish-fixture = {
      description = "Rootless port publish fixture HTTP server";
      wantedBy = [ "multi-user.target" ];
      after = [ "prepare-agent-session.service" ];
      requires = [ "prepare-agent-session.service" ];

      serviceConfig = {
        ExecStart = "${portPublishFixtureServer}/bin/port-publish-fixture-server";
        Restart = "always";
        RestartSec = 1;
        Type = "simple";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    networking.firewall.enable = false;
  };
}
