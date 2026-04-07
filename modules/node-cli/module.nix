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
  devHome = cfg.devHome;
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
  shellBootstrapFunctionNames =
    lib.unique ([ binName ] ++ installBinNames);
  shellBootstrapFunctions =
    lib.concatStringsSep "\n\n"
      (map
        (commandName: ''
          ${commandName}() {
            if command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
              firebreak-bootstrap-wait
            fi
            command ${commandName} "$@"
          }
        '')
        shellBootstrapFunctionNames);
  hostToolRuntimeSeedScript = pkgs.writeShellScript "firebreak-node-cli-host-seed" ''
    set -eu

    tool_home=$1
    local_bin="$tool_home/.local/bin"
    xdg_config_home="$tool_home/.config"
    xdg_cache_home="$tool_home/.cache"
    xdg_state_home="$tool_home/.local/state"
    npm_cache_dir="$xdg_cache_home/npm"
    install_tmp="$xdg_cache_home/tmp"
    install_prefix="$tool_home/.local"
    package_node_modules="$install_prefix/lib/node_modules/${packageSpec}"
    state_root="$xdg_state_home/firebreak-node-cli/${vmName}"
    state_file="$state_root/install-state"
    ready_marker="$tool_home/bootstrap-ready"
    install_state_id='${installStateId}'
    bootstrap_lock_path="$tool_home/.firebreak-bootstrap.lock"
    bootstrap_lock_acquired=0

    log_phase() {
      printf '[firebreak-host-bootstrap] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
    }

    ensure_dir() {
      target_path=$1
      mkdir -p "$target_path"
      chmod 0755 "$target_path" 2>/dev/null || true
    }

    acquire_bootstrap_lock() {
      exec 9>"$bootstrap_lock_path"
      flock 9
      bootstrap_lock_acquired=1
    }

    release_bootstrap_lock() {
      if [ "$bootstrap_lock_acquired" != "1" ]; then
        return 0
      fi
      flock -u 9 2>/dev/null || true
      exec 9>&-
      bootstrap_lock_acquired=0
    }

    write_ready_marker() {
      ready_dir=$(dirname "$ready_marker")
      ensure_dir "$ready_dir"
      ready_tmp=$(mktemp "$ready_dir/.bootstrap-ready.XXXXXX")
      printf '%s\n' "$install_state_id" >"$ready_tmp"
      mv -f "$ready_tmp" "$ready_marker"
    }

    wrappers_ready() {
      for wrapper_name in ${installBinNamesArgs}; do
        if [ ! -x "$local_bin/$wrapper_name" ]; then
          return 1
        fi
      done
      for wrapper_name in ${proxyLocalUpstreamNamesArgs}; do
        if [ ! -x "$local_bin/.firebreak-upstream-$wrapper_name" ]; then
          return 1
        fi
      done
      return 0
    }

    host_trap() {
      exit_code=$?
      release_bootstrap_lock
      exit "$exit_code"
    }
    trap host_trap EXIT INT TERM

    log_phase "toolchain-prepare-start ${displayName}"
    ensure_dir "$tool_home"
    acquire_bootstrap_lock

    for bootstrap_dir in \
      "$state_root" \
      "$local_bin" \
      "$install_prefix" \
      "$install_prefix/lib/node_modules" \
      "$install_tmp" \
      "$xdg_config_home" \
      "$xdg_cache_home" \
      "$xdg_state_home" \
      "$npm_cache_dir"; do
      ensure_dir "$bootstrap_dir"
    done

    if [ -x "$local_bin/${binName}" ] && [ -r "$state_file" ] && [ "$(cat "$state_file")" = "$install_state_id" ] && [ -r "$ready_marker" ] && wrappers_ready; then
      log_phase "toolchain-cache-hit ${packageSpec}"
      exit 0
    fi

    rm -f "$ready_marker"
    log_phase "toolchain-install-start ${packageSpec}"

    bootstrap_env=(
      "HOME=$tool_home"
      "XDG_CONFIG_HOME=$xdg_config_home"
      "XDG_CACHE_HOME=$xdg_cache_home"
      "XDG_STATE_HOME=$xdg_state_home"
      "TMPDIR=$install_tmp"
      "npm_config_cache=$npm_cache_dir"
      "npm_config_prefix=$install_prefix"
      "npm_config_audit=false"
      "npm_config_fund=false"
      "npm_config_update_notifier=false"
      "npm_config_loglevel=warn"
      "CI=1"
      "PATH=$local_bin:$PATH"
    )

    if [ -n "''${HTTP_PROXY:-}" ]; then
      bootstrap_env+=("HTTP_PROXY=$HTTP_PROXY" "npm_config_proxy=$HTTP_PROXY")
    fi
    if [ -n "''${HTTPS_PROXY:-}" ]; then
      bootstrap_env+=("HTTPS_PROXY=$HTTPS_PROXY" "npm_config_https_proxy=$HTTPS_PROXY")
    fi
    if [ -n "''${http_proxy:-}" ]; then
      bootstrap_env+=("http_proxy=$http_proxy")
    fi
    if [ -n "''${https_proxy:-}" ]; then
      bootstrap_env+=("https_proxy=$https_proxy")
    fi
    if [ -n "''${NO_PROXY:-}" ]; then
      bootstrap_env+=("NO_PROXY=$NO_PROXY" "npm_config_noproxy=$NO_PROXY")
    fi
    if [ -n "''${no_proxy:-}" ]; then
      bootstrap_env+=("no_proxy=$no_proxy")
    fi

    env "''${bootstrap_env[@]}" sh -s "$package_node_modules" "${packageSpec}" <<'EOF'
    set -eu
    mkdir -p \
      "$XDG_CONFIG_HOME" \
      "$XDG_CACHE_HOME" \
      "$XDG_STATE_HOME" \
      "$npm_config_cache" \
      "$npm_config_prefix"
    rm -rf "$1"
    rm -f "$npm_config_prefix/bin/${binName}"
    set -- "$2" ${proxyLocalUpstreamInstallArgs}
    npm install --global --omit=dev "$@"
    ${postInstallScript}
    ${installBinScriptSnippet}
    EOF

    printf '%s\n' "$install_state_id" >"$state_file"
    write_ready_marker
    log_phase "toolchain-install-done ${packageSpec}"
    log_phase "wrapper-ready ${binName}"
  '';
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
            upstreamBinPath =
              if proxyLocalUpstream != null
              then proxyLocalUpstream.realBinPath or null
              else null;
            upstreamBinPathArg = lib.escapeShellArg (if upstreamBinPath != null then upstreamBinPath else "");
          in
          ''
            upstream_bin_path=${upstreamBinPathArg}
            if [ -e "$npm_config_prefix/bin/${upstreamBinName}" ]; then
              mv "$npm_config_prefix/bin/${upstreamBinName}" "$npm_config_prefix/bin/.firebreak-upstream-${scriptName}"
            elif [ -n "$upstream_bin_path" ]; then
              ln -sfn "$upstream_bin_path" "$npm_config_prefix/bin/.firebreak-upstream-${scriptName}"
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
  unsupportedCloudHypervisorForwards =
    builtins.filter
      (forward: (forward.from or "host") != "host" || (forward.proto or "tcp") != "tcp")
      forwardPorts;
  launchScript = pkgs.writeShellApplication {
    name = launchCommandName;
    runtimeInputs = with pkgs; [ bash coreutils ];
    text = ''
      set -eu
      workspace=${cfg.workspaceMount}
      exec bash -lc '
        set -eu
        if command -v firebreak-bootstrap-wait >/dev/null 2>&1; then
          firebreak-bootstrap-wait
        fi
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
        READY_MARKER="$ready_marker" BOOTSTRAP_STATE_PATH="$bootstrap_state_path" EXPECTED_INSTALL_STATE_ID='${installStateId}' python3 - <<'PY'
import json
import os
import sys

ready_marker_path = os.environ["READY_MARKER"]
bootstrap_state_path = os.environ["BOOTSTRAP_STATE_PATH"]
expected_install_state_id = os.environ["EXPECTED_INSTALL_STATE_ID"].strip()

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
    bootstrap_state = None
except ValueError:
    bootstrap_state = None

if bootstrap_state is not None:
    expected_install_state_id = (bootstrap_state.get("install_state_id") or "").strip() or expected_install_state_id

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
    "@SHELL_BOOTSTRAP_FUNCTIONS@" = shellBootstrapFunctions;
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
          || builtins.elem "host-port-publish-tcp" backendSpec.capabilities;
        message =
          "workloadVm.runtimeBackend `${cfg.runtimeBackend}` does not support host port publishing required by modules/node-cli forwardPorts.";
      }
      {
        assertion =
          cfg.runtimeBackend != "cloud-hypervisor"
          || unsupportedCloudHypervisorForwards == [ ];
        message =
          "modules/node-cli forwardPorts on cloud-hypervisor currently support only host-originated TCP publishing.";
      }
    ];

    workloadVm = {
      requiredCapabilities = [ "guest-egress" ];
      brandingTagline = tagline;
      environmentOverlay = {
        enable = true;
        package.packages = [ pkgs.nodejs_20 ];
      };
      localPublishedHostPortsJson = builtins.toJSON (
        builtins.filter (forward: (forward.from or "host") == "host") forwardPorts
      );
      sharedStateRoots = sharedStateRoots;
      sharedCredentialSlots = sharedCredentialSlots;
      toolRuntimesEnabled = true;
      memoryMiB = lib.mkDefault memoryMiB;
      extraSystemPackages = with pkgs; [
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
      toolRuntimeSeedScript = if cfg.toolRuntimesEnabled then "${hostToolRuntimeSeedScript}" else null;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };

    microvm.forwardPorts = lib.mkIf (cfg.runtimeBackend == "qemu") forwardPorts;

    networking.firewall.allowedTCPPorts = guestTcpPorts;
    networking.firewall.allowedUDPPorts = guestUdpPorts;
  };
}
