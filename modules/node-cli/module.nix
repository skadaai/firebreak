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
  installBinScripts ? { },
  memoryMiB ? 3072,
  extraSystemPackages ? [ ],
  extraBootstrapPackages ? [ ],
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
  toolsMount = cfg.agentToolsMount;
  localBin = "${devHome}/.local/bin";
  xdgConfigHome = "${devHome}/.config";
  xdgCacheHome = "${devHome}/.cache";
  xdgStateHome = "${devHome}/.local/state";
  npmCacheDir = "${xdgCacheHome}/npm";
  installTmp = "${xdgCacheHome}/tmp";
  installPrefix = "${devHome}/.local";
  packageNodeModules = "${installPrefix}/lib/node_modules/${packageSpec}";
  bootstrapReadyMarker =
    if cfg.agentToolsEnabled
    then "${toolsMount}/bootstrap-ready"
    else "${devHome}/.cache/firebreak-tools/${vmName}/bootstrap-ready";
  installStateId = builtins.hashString "sha256" (builtins.toJSON {
    inherit
      binName
      installBinScripts
      packageSpec
      postInstallScript
      ;
  });
  upstreamInstallBinScriptSnippet =
    lib.concatStringsSep "\n"
      (map
        (scriptName:
          ''
            if [ -e "$npm_config_prefix/bin/${scriptName}" ]; then
              mv "$npm_config_prefix/bin/${scriptName}" "$npm_config_prefix/bin/.firebreak-upstream-${scriptName}"
            else
              rm -f "$npm_config_prefix/bin/.firebreak-upstream-${scriptName}"
            fi
          '')
        (builtins.attrNames installBinScripts));
  installBinScriptSnippet =
    upstreamInstallBinScriptSnippet + "\n" + lib.concatStringsSep "\n"
      (lib.mapAttrsToList
        (scriptName: scriptText:
          let
            heredocName = "FIREBREAK_BIN_${lib.toUpper (builtins.replaceStrings [ "-" "." "/" ] [ "_" "_" "_" ] scriptName)}";
          in
          ''
            mkdir -p "$npm_config_prefix/bin"
            rm -f "$npm_config_prefix/bin/${scriptName}"
            cat >"$npm_config_prefix/bin/${scriptName}" <<'${heredocName}'
            ${scriptText}
            ${heredocName}
            chmod 0755 "$npm_config_prefix/bin/${scriptName}"
          '')
        installBinScripts);
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
      printf 'bootstrap wait: %s\n' 'firebreak-bootstrap-wait'
      ${lib.optionalString (hostForwardSummaries != [ ]) ''
        printf 'forwarded host ports:\n'
        for endpoint in ${lib.escapeShellArgs hostForwardSummaries}; do
          printf '  %s\n' "$endpoint"
        done
      ''}
      printf 'refresh cli: firebreak-refresh-cli\n\n'
    '';
  };
  bootstrapWaitScript = pkgs.writeShellApplication {
    name = "firebreak-bootstrap-wait";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -eu

      ready_marker='${bootstrapReadyMarker}'
      timeout_seconds=''${FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS:-300}
      elapsed_seconds=0

      if [ -z "$timeout_seconds" ]; then
        echo "FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS must be a non-negative integer" >&2
        exit 1
      fi

      case "$timeout_seconds" in
        *[!0-9]*)
          echo "FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS must be a non-negative integer" >&2
          exit 1
          ;;
      esac

      while [ "$elapsed_seconds" -lt "$timeout_seconds" ]; do
        if [ -r "$ready_marker" ]; then
          exit 0
        fi
        sleep 1
        elapsed_seconds=$((elapsed_seconds + 1))
      done

      if [ -r "$ready_marker" ]; then
        exit 0
      fi

      echo "timed out waiting for Firebreak bootstrap readiness marker: $ready_marker" >&2
      exit 1
    '';
  };
  scriptVars = {
    "@BIN_NAME@" = binName;
    "@AGENT_TOOLS_MOUNT@" = toolsMount;
    "@BOOTSTRAP_READY_MARKER@" = bootstrapReadyMarker;
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@DISPLAY_NAME@" = displayName;
    "@EXTRA_SHELL_INIT@" = extraShellInit;
    "@INSTALL_BIN_SCRIPTS@" = installBinScriptSnippet;
    "@INSTALL_STATE_ID@" = installStateId;
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
      agentToolsEnabled = true;
      memoryMiB = lib.mkDefault memoryMiB;
      extraSystemPackages = with pkgs; [
        nodejs_20
        bootstrapWaitScript
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
