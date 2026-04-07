{ self, nixpkgs, microvm, system, guestSystem, renderTemplate, runtimeBackends, nixpkgsConfig }:
let
  lib = nixpkgs.lib;
  pkgs = import nixpkgs {
    inherit system;
    config = nixpkgsConfig;
  };

  mkRunnerPackage = runner:
    pkgs.runCommand "${runner.name}-compat" {
      nativeBuildInputs = with pkgs; [
        coreutils
        gnugrep
        gnused
        python3
      ];
    } ''
      mkdir -p "$out"
      for entry in ${runner}/*; do
        name=$(basename "$entry")
        ln -s "$entry" "$out/$name"
      done
      rm -f "$out/bin"
      mkdir -p "$out/bin"
      for entry in ${runner}/bin/*; do
        name=$(basename "$entry")
        if [ "$name" = "microvm-run" ]; then
          cp --no-preserve=mode,ownership "$entry" "$out/bin/$name"
          chmod u+w+x "$out/bin/$name"
        else
          ln -s "$entry" "$out/bin/$name"
        fi
      done
      if grep -F -q 'aio=io_uring' "$out/bin/microvm-run"; then
        substituteInPlace "$out/bin/microvm-run" \
          --replace-fail 'aio=io_uring' 'aio=threads'
      fi
      if [ "${system}" = "x86_64-linux" ] && grep -F -q -- '-enable-kvm -cpu host,+x2apic,-sgx' "$out/bin/microvm-run"; then
        substituteInPlace "$out/bin/microvm-run" \
          --replace-fail '-enable-kvm -cpu host,+x2apic,-sgx' '$(if [ -r /dev/kvm ]; then printf "%s" "-enable-kvm -cpu host,+x2apic,-sgx"; else printf "%s" "-cpu max"; fi)'
      fi

      ${pkgs.python3}/bin/python3 - "$out/bin/microvm-run" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
match = re.search(r"--cmdline '([^']*)'", text)
if match is None:
    raise SystemExit("microvm-run compatibility wrapper could not locate cloud-hypervisor --cmdline")

firebreak_cmdline_setup = (
    "firebreak_cmdline='" + match.group(1) + "'\n"
    "if [ -n \"''${FIREBREAK_SYSTEMD_UNIT:-}\" ]; then\n"
    "  case \" $firebreak_cmdline \" in\n"
    "    *\" systemd.unit=\"*)\n"
    "      firebreak_cmdline=$(printf '%s\\n' \"$firebreak_cmdline\" | sed -E \"s@(^| )systemd\\\\.unit=[^ ]+@ systemd.unit=''${FIREBREAK_SYSTEMD_UNIT}@\")\n"
    "      firebreak_cmdline=''${firebreak_cmdline# }\n"
    "      ;;\n"
    "    *)\n"
    "      firebreak_cmdline=\"$firebreak_cmdline systemd.unit=''${FIREBREAK_SYSTEMD_UNIT}\"\n"
    "      ;;\n"
    "  esac\n"
    "fi\n\n"
)

text = text.replace("runtime_args=$(", firebreak_cmdline_setup + "runtime_args=$(", 1)
text = re.sub(r"--cmdline '([^']*)'", '--cmdline "$firebreak_cmdline"', text, count=1)
path.write_text(text)
PY

      cat > "$out/bin/firebreak-runner-extra-args" <<'EOF'
firebreak_extra_args=()

if [ -n "''${MICROVM_VFKIT_HOST_CWD_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_HOST_CWD_DIR},mountTag=hostcwd")
fi

if [ -n "''${MICROVM_VFKIT_HOST_META_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_HOST_META_DIR},mountTag=hostmeta")
fi

if [ -n "''${MICROVM_VFKIT_SHARED_STATE_ROOT_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_SHARED_STATE_ROOT_DIR},mountTag=hoststateroot")
fi

if [ -n "''${MICROVM_VFKIT_SHARED_CREDENTIAL_SLOTS_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_SHARED_CREDENTIAL_SLOTS_DIR},mountTag=hostcredentialslots")
fi

if [ -n "''${MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_AGENT_EXEC_OUTPUT_DIR},mountTag=hostexecoutput")
fi

if [ -n "''${MICROVM_VFKIT_AGENT_TOOLS_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_AGENT_TOOLS_DIR},mountTag=hostagenttools")
fi

if [ -n "''${MICROVM_VFKIT_WORKER_BRIDGE_DIR:-}" ]; then
  firebreak_extra_args+=(--device "virtio-fs,sharedDir=''${MICROVM_VFKIT_WORKER_BRIDGE_DIR},mountTag=hostworkerbridge")
fi
EOF
      chmod 0555 "$out/bin/firebreak-runner-extra-args"
    '';

  mkVarVolumeSeedImage = {
    name,
    sizeMiB,
  }:
    pkgs.runCommand "${name}-var-seed.img" {
      nativeBuildInputs = with pkgs; [
        coreutils
        e2fsprogs
      ];
    } ''
      mkdir -p "$out"
      image="$out/${name}-var.img"
      truncate -s ${toString sizeMiB}M "$image"
      mkfs.ext4 -F "$image" >/dev/null
      printf '%s\n' "$image" > "$out/path"
    '';

  mkWorkloadVm = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
    runtimeBackend ? null,
  }:
    nixpkgs.lib.nixosSystem {
      system = guestSystem;
      specialArgs = {
        inherit renderTemplate runtimeBackends;
      };
      modules = [
        microvm.nixosModules.microvm
        self.nixosModules.firebreak-vm-base
        {
          nixpkgs.config = nixpkgsConfig;
        }
        {
          workloadVm.name = name;
          workloadVm.hostSystem = system;
          workloadVm.guestSystem = guestSystem;
          workloadVm.runtimeBackend = lib.mkDefault (
            if runtimeBackend != null then
              runtimeBackend
            else
              runtimeBackends.defaultLocalBackendForHost system
          );
          microvm.vmHostPackages = pkgs;
        }
      ] ++ profileModules ++ extraModules;
    };

  mkWorkloadPackage = {
    name,
    runner,
    runtimeBackend,
    controlSocketName,
    networkMac,
    varVolumeEnabled ? true,
    varVolumeImage,
    varVolumeSeedImage,
    defaultAgentCommand ? "",
    agentConfigSubdir ? "agent",
    defaultAgentConfigHostDir,
    defaultCredentialSlotsHostDir ? "$HOME/.firebreak/credentials",
    workspaceBootstrapConfigHostDir ? "",
    hostConfigAdoptionEnabled ? false,
    agentEnvPrefix ? "AGENT",
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    workerBridgeEnabled ? false,
    localPublishedHostPortsJson ? "[]",
    guestEgressEnabled ? false,
    guestEgressProxyPort ? 3128,
    toolRuntimeSeedScript ? "",
    environmentOverlayEnable ? true,
    environmentOverlayPackageInstallablesJson ? "[]",
    environmentOverlayPackagePathsJson ? "[]",
    environmentOverlayPackageExportsJson ? "{}",
    environmentOverlayProjectNixEnabled ? false,
    commandBootBaseSystemdUnit ? "",
    interactiveBootBaseSystemdUnit ? "",
  }:
    let
      runnerWrapper = pkgs.writeShellScript "firebreak-runner-wrapper" ''
        set -eu
        . ${runner}/bin/firebreak-runner-extra-args
        exec ${runner}/bin/microvm-run "$@" "''${firebreak_extra_args[@]}"
      '';
      wrapperTemplateVars = {
        "@HOST_SYSTEM@" = system;
        "@RUNTIME_BACKEND@" = runtimeBackend;
        "@CONTROL_SOCKET@" = "${controlSocketName}.socket";
        "@NETWORK_MAC@" = networkMac;
        "@VAR_VOLUME_ENABLED@" = if varVolumeEnabled then "1" else "0";
        "@VAR_VOLUME_IMAGE@" = varVolumeImage;
        "@VAR_VOLUME_SEED_IMAGE@" = varVolumeSeedImage;
        "@DEFAULT_AGENT_COMMAND@" = defaultAgentCommand;
        "@PACKAGE_NAME@" = name;
        "@RUNNER@" = "${runnerWrapper}";
        "@STATE_SUBDIR@" = agentConfigSubdir;
        "@DEFAULT_STATE_ROOT@" = defaultAgentConfigHostDir;
        "@DEFAULT_CREDENTIAL_SLOTS_HOST_DIR@" = defaultCredentialSlotsHostDir;
        "@WORKSPACE_BOOTSTRAP_CONFIG_HOST_DIR@" = workspaceBootstrapConfigHostDir;
        "@HOST_CONFIG_ADOPTION_ENABLED@" = if hostConfigAdoptionEnabled then "1" else "0";
        "@AGENT_ENV_PREFIX@" = agentEnvPrefix;
        "@SHARED_STATE_ROOT_ENABLED@" = if (sharedStateRoots.enable or false) then "1" else "0";
        "@SHARED_CREDENTIAL_SLOTS_ENABLED@" = if (sharedCredentialSlots.enable or false) then "1" else "0";
        "@LOCAL_PUBLISHED_HOST_PORTS_JSON@" = localPublishedHostPortsJson;
        "@GUEST_EGRESS_ENABLED@" = if guestEgressEnabled then "1" else "0";
        "@GUEST_EGRESS_PROXY_PORT@" = toString guestEgressProxyPort;
        "@FIREBREAK_FLAKE_REF@" = "path:${builtins.toString ../../.}";
        "@WORKER_BRIDGE_ENABLED@" = if workerBridgeEnabled then "1" else "0";
        "@ENVIRONMENT_OVERLAY_ENABLE@" = if environmentOverlayEnable then "1" else "0";
        "@ENVIRONMENT_OVERLAY_PACKAGE_INSTALLABLES_JSON@" = environmentOverlayPackageInstallablesJson;
        "@ENVIRONMENT_OVERLAY_PACKAGE_PATHS_JSON@" = environmentOverlayPackagePathsJson;
        "@ENVIRONMENT_OVERLAY_PACKAGE_EXPORTS_JSON@" = environmentOverlayPackageExportsJson;
        "@ENVIRONMENT_OVERLAY_PROJECT_NIX_ENABLED@" = if environmentOverlayProjectNixEnabled then "1" else "0";
        "@COMMAND_BOOT_BASE_SYSTEMD_UNIT@" = commandBootBaseSystemdUnit;
        "@INTERACTIVE_BOOT_BASE_SYSTEMD_UNIT@" = interactiveBootBaseSystemdUnit;
        "@FIREBREAK_NIXPKGS_PATH@" = "${pkgs.path}";
      };
      renderedCloudHypervisorNetworkLib = renderTemplate
        (wrapperTemplateVars // {
          "@FIREBREAK_CLOUD_HYPERVISOR_PORT_PUBLISH_PROXY_PY@" = builtins.readFile ../../modules/profiles/local/host/cloud-hypervisor-port-publish.py;
        })
        ../../modules/profiles/local/host/cloud-hypervisor-network.sh;
      renderedCloudHypervisorVsockLib = renderTemplate
        (wrapperTemplateVars // {
          "@FIREBREAK_CLOUD_HYPERVISOR_EGRESS_PROXY_PY@" = builtins.readFile ../../modules/profiles/local/host/cloud-hypervisor-egress-proxy.py;
        })
        ../../modules/profiles/local/host/cloud-hypervisor-vsock.sh;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs =
        with pkgs;
        [
          bash
          coreutils
          git
          gnused
          nix
          python3
          sudo
          util-linux
        ]
        ++ lib.optionals (toolRuntimeSeedScript != "") [
          nodejs_20
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          iproute2
          iptables
          socat
          virtiofsd
        ];
      text = renderTemplate (wrapperTemplateVars // {
        "@FIREBREAK_PROJECT_CONFIG_LIB@" = builtins.readFile ../../modules/base/host/firebreak-project-config.sh;
        "@FIREBREAK_ENVIRONMENT_LIB@" = builtins.readFile ../../modules/base/host/firebreak-environment.sh;
        "@FIREBREAK_WORKER_LIB@" = builtins.readFile ../../modules/base/host/firebreak-worker.sh;
        "@FIREBREAK_WORKER_BRIDGE_HOST_LIB@" = builtins.readFile ../../modules/profiles/local/host/firebreak-worker-bridge-host.sh;
        "@FIREBREAK_CLOUD_HYPERVISOR_NETWORK_LIB@" = renderedCloudHypervisorNetworkLib;
        "@FIREBREAK_CLOUD_HYPERVISOR_VSOCK_LIB@" = renderedCloudHypervisorVsockLib;
        "@FIREBREAK_LOCAL_COMMAND_REQUEST_LIB@" = builtins.readFile ../../modules/profiles/local/host/command-request.sh;
        "@FIREBREAK_LOCAL_INSTANCE_CONTROLLER_LIB@" = builtins.readFile ../../modules/profiles/local/host/local-instance-controller.sh;
        "@FIREBREAK_PROFILE_SUMMARY_SCRIPT@" = builtins.toString ../../modules/profiles/local/host/profile-summary.py;
        "@PYTHON3@" = "${pkgs.python3}/bin/python3";
        "@TOOL_RUNTIME_SEED_SCRIPT@" = toolRuntimeSeedScript;
      }) ../../modules/profiles/local/host/run-wrapper.sh;
    };

  mkLocalVmPackage = {
    name,
    runnerPackage,
    runtimeBackend,
    controlSocketName ? name,
    networkMac,
    varVolumeEnabled ? true,
    varVolumeImage,
    varVolumeSeedImage,
    defaultAgentCommand ? "",
    agentConfigSubdir ? "agent",
    defaultAgentConfigHostDir ? "$HOME/.firebreak",
    defaultCredentialSlotsHostDir ? "$HOME/.firebreak/credentials",
    workspaceBootstrapConfigHostDir ? "",
    hostConfigAdoptionEnabled ? false,
    agentEnvPrefix ? "AGENT",
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    workerBridgeEnabled ? false,
    localPublishedHostPortsJson ? "[]",
    guestEgressEnabled ? false,
    guestEgressProxyPort ? 3128,
    toolRuntimeSeedScript ? "",
    environmentOverlayEnable ? true,
    environmentOverlayPackageInstallablesJson ? "[]",
    environmentOverlayPackagePathsJson ? "[]",
    environmentOverlayPackageExportsJson ? "{}",
    environmentOverlayProjectNixEnabled ? false,
    commandBootBaseSystemdUnit ? "",
    interactiveBootBaseSystemdUnit ? "",
  }:
    mkWorkloadPackage {
      inherit
        name
        runtimeBackend
        controlSocketName
        networkMac
        varVolumeEnabled
        varVolumeImage
        varVolumeSeedImage
        defaultAgentCommand
        agentConfigSubdir
        defaultAgentConfigHostDir
        defaultCredentialSlotsHostDir
        workspaceBootstrapConfigHostDir
        hostConfigAdoptionEnabled
        agentEnvPrefix
        sharedStateRoots
        sharedCredentialSlots
        workerBridgeEnabled
        localPublishedHostPortsJson
        guestEgressEnabled
        guestEgressProxyPort
        toolRuntimeSeedScript
        environmentOverlayEnable
        environmentOverlayPackageInstallablesJson
        environmentOverlayPackagePathsJson
        environmentOverlayPackageExportsJson
        environmentOverlayProjectNixEnabled
        commandBootBaseSystemdUnit
        interactiveBootBaseSystemdUnit;
      runner = runnerPackage;
    };

  mkLocalVmArtifacts = {
    name,
    extraModules ? [ ],
    profileModules ? [ self.nixosModules.firebreak-local-profile ],
    runtimeBackend ? null,
    controlSocketName ? name,
    defaultAgentCommand ? "",
    agentConfigSubdir ? "agent",
    defaultAgentConfigHostDir ? "$HOME/.firebreak",
    defaultCredentialSlotsHostDir ? "$HOME/.firebreak/credentials",
    workspaceBootstrapConfigHostDir ? "",
    hostConfigAdoptionEnabled ? false,
    agentEnvPrefix ? "AGENT",
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    workerBridgeEnabled ? false,
    workerKinds ? { },
  }:
    let
      nixosConfiguration = mkWorkloadVm {
        inherit name profileModules runtimeBackend;
        extraModules =
          extraModules
          ++ nixpkgs.lib.optional (workerKinds != { }) {
            workloadVm.workerKindsJson = builtins.toJSON workerKinds;
          }
          ++ nixpkgs.lib.optional workerBridgeEnabled {
            workloadVm.workerBridgeEnabled = true;
          };
      };
      runnerPackage = mkRunnerPackage nixosConfiguration.config.microvm.declaredRunner;
      varVolumeEnabled = nixosConfiguration.config.workloadVm.varVolumeEnabled;
      varVolumeSeedImage =
        if varVolumeEnabled then
          mkVarVolumeSeedImage {
            inherit name;
            sizeMiB = nixosConfiguration.config.workloadVm.varVolumeSizeMiB;
          }
        else
          null;
      package = mkLocalVmPackage {
        inherit
          name
          runnerPackage
          controlSocketName
          defaultAgentCommand
          agentConfigSubdir
          defaultAgentConfigHostDir
          defaultCredentialSlotsHostDir
          workspaceBootstrapConfigHostDir
          hostConfigAdoptionEnabled
          agentEnvPrefix
          sharedStateRoots
          sharedCredentialSlots
          workerBridgeEnabled;
        runtimeBackend = nixosConfiguration.config.workloadVm.runtimeBackend;
        networkMac = nixosConfiguration.config.workloadVm.macAddress;
        inherit varVolumeEnabled;
        varVolumeImage = nixosConfiguration.config.workloadVm.varVolumeImage;
        varVolumeSeedImage =
          if varVolumeSeedImage == null then
            ""
          else
            "${varVolumeSeedImage}/${name}-var.img";
        localPublishedHostPortsJson = nixosConfiguration.config.workloadVm.localPublishedHostPortsJson;
        guestEgressEnabled = nixosConfiguration.config.workloadVm.guestEgress.enable;
        guestEgressProxyPort = nixosConfiguration.config.workloadVm.guestEgress.proxyPort;
        toolRuntimeSeedScript =
          if nixosConfiguration.config.workloadVm.toolRuntimeSeedScript == null then
            ""
          else
            nixosConfiguration.config.workloadVm.toolRuntimeSeedScript;
        environmentOverlayEnable = nixosConfiguration.config.workloadVm.environmentOverlay.enable;
        environmentOverlayPackageInstallablesJson =
          builtins.toJSON nixosConfiguration.config.workloadVm.environmentOverlay.package.installables;
        environmentOverlayPackagePathsJson =
          builtins.toJSON nixosConfiguration.config.workloadVm.environmentOverlay.package.pathPrefixes;
        environmentOverlayPackageExportsJson =
          builtins.toJSON nixosConfiguration.config.workloadVm.environmentOverlay.package.exports;
        environmentOverlayProjectNixEnabled =
          nixosConfiguration.config.workloadVm.environmentOverlay.projectNix.enable;
        commandBootBaseSystemdUnit =
          nixosConfiguration.config.workloadVm.bootBases.command.systemdUnit;
        interactiveBootBaseSystemdUnit =
          nixosConfiguration.config.workloadVm.bootBases.interactive.systemdUnit;
      };
    in {
      inherit nixosConfiguration package runnerPackage varVolumeSeedImage;
  };
in {
  inherit
    mkWorkloadPackage
    mkWorkloadVm
    mkLocalVmArtifacts
    mkLocalVmPackage
    mkRunnerPackage
    runtimeBackends
    ;
}
