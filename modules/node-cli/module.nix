{
  vmName,
  displayName,
  tagline,
  binName,
  packageSpec,
  launchCommand,
  launchCommandName,
  readyCommandName,
  launchEnvironment ? { },
  forwardPorts ? [ ],
  postInstallScript ? "",
  memoryMiB ? 3072,
  extraSystemPackages ? [ ],
  extraBootstrapPackages ? [ ],
  sharedAgentConfig ? { },
  extraShellInit ? "",
}:
moduleArgs@{
  config,
  lib,
  pkgs,
  renderTemplate,
  ...
}:
let
  cfg = config.agentVm;
  devHome = "/var/lib/${cfg.devUser}";
  localBin = "${devHome}/.local/bin";
  xdgConfigHome = "${devHome}/.config";
  xdgCacheHome = "${devHome}/.cache";
  xdgStateHome = "${devHome}/.local/state";
  npmCacheDir = "${xdgCacheHome}/npm";
  installTmp = "${xdgCacheHome}/tmp";
  installPrefix = "${devHome}/.local";
  packageNodeModules = "${installPrefix}/lib/node_modules/${packageSpec}";
  launchEnvironmentExports = lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") launchEnvironment);
  hostForwardSummaries =
    map
      (forward:
        let
          host = forward.host or { };
          guest = forward.guest or { };
          proto = forward.proto or "tcp";
          hostAddress = host.address or "127.0.0.1";
          guestAddress = guest.address or "0.0.0.0";
        in
        "${proto} ${hostAddress}:${toString host.port} -> ${guestAddress}:${toString guest.port}"
      )
      (builtins.filter (forward: (forward.from or "host") == "host") forwardPorts);
  guestTcpPorts =
    lib.unique (map (forward: forward.guest.port)
      (builtins.filter (forward: (forward.proto or "tcp") == "tcp") forwardPorts));
  guestUdpPorts =
    lib.unique (map (forward: forward.guest.port)
      (builtins.filter (forward: (forward.proto or "tcp") == "udp") forwardPorts));
  launchScript = pkgs.writeShellApplication {
    name = launchCommandName;
    runtimeInputs = with pkgs; [ bash coreutils ];
    text = ''
      set -eu
      workspace=${cfg.workspaceMount}
      exec bash -lc '
        set -eu
        ${launchEnvironmentExports}
        cd "$1"
        ${launchCommand}
      ' bash "$workspace"
    '';
  };
  readyScript = pkgs.writeShellApplication {
    name = readyCommandName;
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -eu
      printf '\n%s sandbox ready.\n' '${displayName}'
      printf 'workspace: %s\n' '${cfg.workspaceMount}'
      printf 'default command: %s\n' '${launchCommand}'
      printf 'cli binary: %s\n' '${binName}'
      ${lib.optionalString (hostForwardSummaries != [ ]) ''
        printf 'forwarded host ports:\n'
        for endpoint in ${lib.escapeShellArgs hostForwardSummaries}; do
          printf '  %s\n' "$endpoint"
        done
      ''}
      printf 'refresh cli: firebreak-refresh-cli\n\n'
    '';
  };
  scriptVars = {
    "@BIN_NAME@" = binName;
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@DISPLAY_NAME@" = displayName;
    "@EXTRA_SHELL_INIT@" = extraShellInit;
    "@LAUNCH_COMMAND_NAME@" = launchCommandName;
    "@LAUNCH_ENV_EXPORTS@" = launchEnvironmentExports;
    "@LOCAL_BIN@" = localBin;
    "@NAME@" = vmName;
    "@NPM_CACHE_DIR@" = npmCacheDir;
    "@PACKAGE_NODE_MODULES@" = packageNodeModules;
    "@PACKAGE_SPEC@" = packageSpec;
    "@POST_INSTALL_SCRIPT@" = postInstallScript;
    "@READY_COMMAND_NAME@" = readyCommandName;
    "@TMPDIR@" = installTmp;
    "@XDG_CACHE_HOME@" = xdgCacheHome;
    "@XDG_CONFIG_HOME@" = xdgConfigHome;
    "@XDG_STATE_HOME@" = xdgStateHome;
  };
in {
  config = {
    agentVm = {
      brandingTagline = tagline;
      agentConfigEnabled = false;
      sharedAgentConfig = sharedAgentConfig;
      memoryMiB = lib.mkDefault memoryMiB;
      extraSystemPackages = with pkgs; [
        nodejs_20
        launchScript
        readyScript
      ] ++ extraSystemPackages;
      bootstrapPackages = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        nodejs_20
        util-linux
      ] ++ extraBootstrapPackages;
      bootstrapScript = renderTemplate scriptVars ./guest/bootstrap.sh;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };

    microvm.forwardPorts = forwardPorts;

    networking.firewall.allowedTCPPorts = guestTcpPorts;
    networking.firewall.allowedUDPPorts = guestUdpPorts;
  };
}
