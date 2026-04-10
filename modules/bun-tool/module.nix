moduleArgs:
{
  vmName,
  displayName,
  binName,
  packageSpec,
  promptCommand,
  configSelectorPrefix,
  configSubdir,
  configExports,
  credentialFileBindings ? [ ],
  credentialEnvBindings ? [ ],
  credentialHelperBindings ? [ ],
  credentialLoginArgs ? [ ],
  credentialLoginMaterialization ? "none",
  extraSystemPackages ? [ ],
  bootstrapPackages ? [ ],
}:
let
  inherit (moduleArgs) config lib pkgs renderTemplate;
  cfg = config.workloadVm;
  hasCredentialAdapters =
    credentialFileBindings != [ ]
    || credentialEnvBindings != [ ]
    || credentialHelperBindings != [ ]
    || credentialLoginArgs != [ ]
    || credentialLoginMaterialization != "none";
  devHome = "/var/lib/${cfg.devUser}";
  toolsMount = cfg.toolRuntimesMount;
  bootstrapReadyMarker =
    if cfg.toolRuntimesEnabled
    then "${toolsMount}/bootstrap-ready"
    else "${devHome}/.cache/firebreak-tools/${vmName}/bootstrap-ready";
  bootstrapWaitScript = pkgs.writeShellApplication {
    name = "firebreak-bootstrap-wait";
    runtimeInputs = with pkgs; [ coreutils gnugrep ];
    text = ''
      set -eu

      ready_marker='${bootstrapReadyMarker}'
      state_path='/run/firebreak-worker/bootstrap-state.json'
      timeout_seconds=''${FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS:-300}
      elapsed_seconds=0

      case "$timeout_seconds" in
        ""|*[!0-9]*)
          echo "FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS must be a non-negative integer" >&2
          exit 1
          ;;
      esac

      while [ "$elapsed_seconds" -lt "$timeout_seconds" ]; do
        if [ -r "$ready_marker" ]; then
          exit 0
        fi
        if [ -r "$state_path" ] && grep -F -q '"status": "error"' "$state_path"; then
          cat "$state_path" >&2
          exit 1
        fi
        sleep 1
        elapsed_seconds=$((elapsed_seconds + 1))
      done

      if [ -r "$ready_marker" ]; then
        exit 0
      fi

      if [ -r "$state_path" ]; then
        cat "$state_path" >&2
      fi
      echo "timed out waiting for Firebreak bootstrap readiness marker: $ready_marker" >&2
      exit 1
    '';
  };
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@TOOL_BIN@" = binName;
    "@TOOL_PACKAGE_SPEC@" = packageSpec;
    "@STATE_ENV_EXPORTS@" = configExports;
    "@STATE_MODE_SELECTOR_VAR@" = "${configSelectorPrefix}_STATE_MODE";
    "@STATE_SUBDIR@" = configSubdir;
    "@TOOL_DISPLAY_NAME@" = displayName;
    "@COMMAND_OUTPUT_MOUNT@" = cfg.workerExecOutputMount;
    "@TOOL_RUNTIMES_MOUNT@" = toolsMount;
    "@BOOTSTRAP_READY_MARKER@" = bootstrapReadyMarker;
  };
in {
  config = {
    workloadVm = {
      name = lib.mkDefault vmName;
      toolRuntimesEnabled = true;
      sharedStateRoots = {
        enable = true;
        tools.${binName} = {
          displayName = displayName;
          selectorPrefix = configSelectorPrefix;
          configSubdir = configSubdir;
          configEnvExports = configExports;
        } // lib.optionalAttrs hasCredentialAdapters {
          credentials = {
            slotSubdir = configSubdir;
            fileBindings = credentialFileBindings;
            envBindings = credentialEnvBindings;
            helperBindings = credentialHelperBindings;
            loginArgs = credentialLoginArgs;
            loginMaterialization = credentialLoginMaterialization;
          };
        };
      };
      sharedCredentialSlots.enable = hasCredentialAdapters;
      defaultCommand = binName;
      promptCommand = promptCommand;
      extraSystemPackages = with pkgs; [
        bun
        bootstrapWaitScript
        git
        nodejs
      ] ++ extraSystemPackages;
      bootstrapPackages = with pkgs; [
        bun
        coreutils
        nodejs
        util-linux
      ] ++ bootstrapPackages;
      bootstrapScript = renderTemplate scriptVars ./guest/bootstrap.sh;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };
  };
}
