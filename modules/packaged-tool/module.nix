moduleArgs:
{
  vmName,
  displayName,
  binName,
  package,
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
  extraEnvironmentPackages ? [ ],
}:
let
  inherit (moduleArgs) config lib pkgs renderTemplate;
  cfg = config.workloadVm;
  devHome = cfg.devHome;
  scriptVars = {
    "@DEV_HOME@" = devHome;
    "@DEV_USER@" = cfg.devUser;
    "@STATE_ENV_EXPORTS@" = configExports;
    "@STATE_MODE_SELECTOR_VAR@" = "${configSelectorPrefix}_STATE_MODE";
    "@STATE_SUBDIR@" = configSubdir;
    "@TOOL_DISPLAY_NAME@" = displayName;
  };
in {
  config = {
    workloadVm = {
      guestSudoEnable = lib.mkDefault false;
      coldExecBootstrapWaitEnable = lib.mkDefault false;
      requiredCapabilities = [ "guest-egress" ];
      name = lib.mkDefault vmName;
      sharedStateRoots = {
        enable = true;
        tools.${binName} = {
          displayName = displayName;
          realBinName = binName;
          realBinPath = "${package}/bin/${binName}";
          selectorPrefix = configSelectorPrefix;
          configSubdir = configSubdir;
          configEnvExports = configExports;
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
      sharedCredentialSlots.enable = true;
      defaultCommand = binName;
      promptCommand = promptCommand;
      environmentOverlay = {
        enable = extraEnvironmentPackages != [ ];
        package.packages = extraEnvironmentPackages;
      };
      extraSystemPackages = [ package ] ++ extraSystemPackages;
      shellInit = renderTemplate scriptVars ./guest/shell-init.sh;
    };
  };
}
