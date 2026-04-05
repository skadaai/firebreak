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
  proxyLocalUpstreams ? { },
  memoryMiB ? 3072,
  extraSystemPackages ? [ ],
  extraBootstrapPackages ? [ ],
  sharedStateRoots ? { },
  sharedCredentialSlots ? { },
  extraShellInit ? "",
}:
moduleArgs@{
  config,
  lib,
  pkgs,
  renderTemplate,
  runtimeBackends,
  ...
}:
let
  cfg = config.workloadVm;
  backendSpec = runtimeBackends.specFor cfg.runtimeBackend;
  devHome = "/var/lib/${cfg.devUser}";
  toolsMount = cfg.toolRuntimesMount;
  localBin = "${devHome}/.local/bin";
  xdgConfigHome = "${devHome}/.config";
  xdgCacheHome = "${devHome}/.cache";
  xdgStateHome = "${devHome}/.local/state";
  npmCacheDir = "${xdgCacheHome}/npm";
  installTmp = "${xdgCacheHome}/tmp";
  installPrefix = "${devHome}/.local";
  packageNodeModules = "${installPrefix}/lib/node_modules/${packageSpec}";
  bootstrapReadyMarker =
    if cfg.toolRuntimesEnabled
    then "${toolsMount}/bootstrap-ready"
    else "${devHome}/.cache/firebreak-tools/${vmName}/bootstrap-ready";
  installStateId = builtins.hashString "sha256" (builtins.toJSON {
    inherit
      binName
      installBinScripts
      packageSpec
      postInstallScript
      proxyLocalUpstreams
      ;
  });
  proxyLocalUpstreamSpecs =
    lib.unique (
      lib.filter (value: value != null)
        (lib.mapAttrsToList (_commandName: upstream: upstream.packageSpec or null) proxyLocalUpstreams)
    );
  installBinNames = builtins.attrNames installBinScripts;
  proxyLocalUpstreamNames = builtins.attrNames proxyLocalUpstreams;
  proxyLocalUpstreamInstallArgs = lib.escapeShellArgs proxyLocalUpstreamSpecs;
  installBinNamesArgs = lib.escapeShellArgs installBinNames;
  proxyLocalUpstreamNamesArgs = lib.escapeShellArgs proxyLocalUpstreamNames;
  upstreamInstallBinScriptSnippet =
    lib.concatStringsSep "\n"
      (map
        (scriptName:
          let
            proxyLocalUpstream =
              if builtins.hasAttr scriptName proxyLocalUpstreams
              then builtins.getAttr scriptName proxyLocalUpstreams
              else null;
            upstreamBinName =
              if proxyLocalUpstream != null
              then proxyLocalUpstream.binName or scriptName
              else scriptName;
          in
          ''
            if [ -e "$npm_config_prefix/bin/${upstreamBinName}" ]; then
              mv "$npm_config_prefix/bin/${upstreamBinName}" "$npm_config_prefix/bin/.firebreak-upstream-${scriptName}"
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
            shortHash = builtins.substring 0 12 (builtins.hashString "sha256" "${scriptName}:${scriptText}");
            heredocName = "FIREBREAK_BIN_${lib.toUpper (builtins.replaceStrings [ "-" "." "/" ] [ "_" "_" "_" ] scriptName)}_${shortHash}";
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
    runtimeInputs = with pkgs; [ coreutils python3 ];
    text = ''
      set -eu

      ready_marker='${bootstrapReadyMarker}'
      bootstrap_state_path=''${FIREBREAK_BOOTSTRAP_STATE_PATH:-/run/firebreak-worker/bootstrap-state.json}
      timeout_seconds=''${FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS:-300}
      elapsed_seconds=0

      report_bootstrap_error() {
        BOOTSTRAP_STATE_PATH="$bootstrap_state_path" python3 - <<'PY'
import json
import os
import sys

path = os.environ["BOOTSTRAP_STATE_PATH"]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except OSError:
    raise SystemExit(1)
except ValueError:
    raise SystemExit(1)

if data.get("status") != "error":
    raise SystemExit(1)

phase = data.get("phase") or "unknown"
detail = data.get("detail") or "bootstrap failed"
print(f"Firebreak bootstrap failed during {phase}: {detail}", file=sys.stderr)
PY
      }

      validate_ready_marker() {
        READY_MARKER="$ready_marker" BOOTSTRAP_STATE_PATH="$bootstrap_state_path" python3 - <<'PY'
import json
import os
import sys

ready_marker_path = os.environ["READY_MARKER"]
bootstrap_state_path = os.environ["BOOTSTRAP_STATE_PATH"]

try:
    with open(ready_marker_path, "r", encoding="utf-8") as handle:
        ready_marker_value = handle.read().strip()
except OSError:
    raise SystemExit(1)

if not ready_marker_value:
    raise SystemExit(1)

try:
    with open(bootstrap_state_path, "r", encoding="utf-8") as handle:
        bootstrap_state = json.load(handle)
except OSError:
    raise SystemExit(1)
except ValueError:
    raise SystemExit(1)

expected_install_state_id = (bootstrap_state.get("install_state_id") or "").strip()
if not expected_install_state_id:
    raise SystemExit(1)

if ready_marker_value != expected_install_state_id:
    raise SystemExit(1)
PY
      }

      case "$timeout_seconds" in
        *[!0-9]*)
          echo "FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS must be a non-negative integer" >&2
          exit 1
          ;;
      esac

      while [ "$elapsed_seconds" -lt "$timeout_seconds" ]; do
        if validate_ready_marker; then
          exit 0
        fi
        if report_bootstrap_error; then
          exit 1
        fi
        sleep 1
        elapsed_seconds=$((elapsed_seconds + 1))
      done

      if validate_ready_marker; then
        exit 0
      fi

      if report_bootstrap_error; then
        exit 1
      fi

      echo "timed out waiting for Firebreak bootstrap readiness marker: $ready_marker" >&2
      exit 1
    '';
  };
  bootstrapConditionScript = pkgs.writeShellScript "firebreak-bootstrap-condition" ''
    set -eu

    tool_home='${toolsMount}'
    if ! [ -d "$tool_home" ]; then
      tool_home='${devHome}'
    fi

    local_bin="$tool_home/.local/bin"
    xdg_state_home="$tool_home/.local/state"
    state_file="$xdg_state_home/firebreak-node-cli/${vmName}/install-state"
    ready_marker='${bootstrapReadyMarker}'
    install_state_id='${installStateId}'

    wrappers_ready() {
      for wrapper_name in ${installBinNamesArgs}; do
        if ! [ -x "$local_bin/$wrapper_name" ]; then
          return 1
        fi
      done
      for wrapper_name in ${proxyLocalUpstreamNamesArgs}; do
        if ! [ -x "$local_bin/.firebreak-upstream-$wrapper_name" ]; then
          return 1
        fi
      done
      return 0
    }

    if [ -x "$local_bin/${binName}" ] \
      && [ -r "$state_file" ] \
      && [ "$(cat "$state_file")" = "$install_state_id" ] \
      && [ -r "$ready_marker" ] \
      && wrappers_ready; then
      exit 1
    fi

    exit 0
  '';
  scriptVars = {
    "@AGENT_EXEC_OUTPUT_MOUNT@" = cfg.workerExecOutputMount;
    "@BIN_NAME@" = binName;
    "@AGENT_TOOLS_MOUNT@" = toolsMount;
    "@BOOTSTRAP_READY_MARKER@" = bootstrapReadyMarker;
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@DISPLAY_NAME@" = displayName;
    "@EXTRA_SHELL_INIT@" = extraShellInit;
    "@INSTALL_BIN_SCRIPTS@" = installBinScriptSnippet;
    "@INSTALL_BIN_NAMES@" = installBinNamesArgs;
    "@PROXY_LOCAL_UPSTREAM_NAMES@" = proxyLocalUpstreamNamesArgs;
    "@INSTALL_STATE_ID@" = installStateId;
    "@LAUNCH_COMMAND_NAME@" = launchCommandName;
    "@LAUNCH_ENV_EXPORTS@" = launchEnvironmentExports;
    "@LOCAL_BIN@" = localBin;
    "@NAME@" = vmName;
    "@NPM_CACHE_DIR@" = npmCacheDir;
    "@PACKAGE_NODE_MODULES@" = packageNodeModules;
    "@PROXY_LOCAL_UPSTREAM_INSTALL_ARGS@" = proxyLocalUpstreamInstallArgs;
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
    assertions = [
      {
        assertion =
          forwardPorts == [ ]
          || builtins.elem "local-port-publish" backendSpec.capabilities;
        message =
          "workloadVm.runtimeBackend `${cfg.runtimeBackend}` does not support host port publishing required by modules/node-cli forwardPorts.";
      }
    ];

    workloadVm = {
      brandingTagline = tagline;
      sharedStateRoots = sharedStateRoots;
      sharedCredentialSlots = sharedCredentialSlots;
      toolRuntimesEnabled = true;
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
        python3
        util-linux
      ] ++ extraBootstrapPackages;
      bootstrapConditionScript = "${bootstrapConditionScript}";
      bootstrapScript = renderTemplate scriptVars ./guest/bootstrap.sh;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };

    microvm.forwardPorts = forwardPorts;

    networking.firewall.allowedTCPPorts = guestTcpPorts;
    networking.firewall.allowedUDPPorts = guestUdpPorts;
  };
}
