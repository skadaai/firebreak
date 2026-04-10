{ lib, pkgs, renderTemplate, mkLocalVmArtifacts }:
rec {
  workerProxyLocalUpstreamsByPackage = {
    firebreak-codex = {
      binName = "codex";
      package = pkgs.codex;
    };
    firebreak-claude-code = {
      binName = "claude";
      package = pkgs.claude-code;
    };
  };

  mkWorkerProxyScript =
    {
      commandName ? kind,
      kind,
      defaultMode ? null,
      defaultWorkerMode ? "local",
    }:
    ''
      #!/usr/bin/env bash
      set -eu

      script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
      upstream_bin=""
      upstream_candidates=(
        "$script_dir/.firebreak-upstream-${commandName}"
      )
      if [ -n "''${LOCAL_BIN:-}" ]; then
        upstream_candidates+=("''${LOCAL_BIN}/.firebreak-upstream-${commandName}")
      fi
      if [ -n "''${npm_config_prefix:-}" ]; then
        upstream_candidates+=("''${npm_config_prefix}/bin/.firebreak-upstream-${commandName}")
      fi
      if [ -n "''${HOME:-}" ]; then
        upstream_candidates+=("''${HOME}/.local/bin/.firebreak-upstream-${commandName}")
      fi
      for upstream_candidate in "''${upstream_candidates[@]}"; do
        if [ -x "$upstream_candidate" ]; then
          upstream_bin=$upstream_candidate
          break
        fi
      done
      if [ -z "$upstream_bin" ]; then
        upstream_bin="''${upstream_candidates[0]}"
      fi
      default_worker_mode=${lib.escapeShellArg defaultWorkerMode}
      proxy_default_mode=${lib.escapeShellArg (if defaultMode == null then "" else defaultMode)}

      normalize_worker_mode() {
        case "$1" in
          worker)
            printf '%s\n' "vm"
            ;;
          *)
            printf '%s\n' "$1"
            ;;
        esac
      }

      json_escape() {
        printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
      }

      worker_command_needs_attach() {
        if [ "$#" -eq 0 ]; then
          return 0
        fi

        case "$1" in
          --help|-h|help|--version|-V|version)
            return 1
            ;;
        esac

        return 0
      }

      resolve_command_worker_mode() {
        raw_modes=$1
        if [ -z "$raw_modes" ]; then
          return 0
        fi

        raw_modes=$(printf '%s' "$raw_modes" | tr '\n' ',')
        case ",$raw_modes," in
          *",${commandName}="*)
            resolved_mode=''${raw_modes#*"${commandName}="}
            resolved_mode=''${resolved_mode%%,*}
            if [ -n "$resolved_mode" ]; then
              printf '%s\n' "$(normalize_worker_mode "$resolved_mode")"
            fi
            ;;
        esac
      }

      worker_mode_overrides=''${FIREBREAK_WORKER_MODES:-}
      if [ -z "$worker_mode_overrides" ] && [ -r /run/firebreak-worker/worker-modes ]; then
        worker_mode_overrides=$(cat /run/firebreak-worker/worker-modes)
      fi

      worker_mode=$(resolve_command_worker_mode "$worker_mode_overrides" || true)
      if [ -z "$worker_mode" ]; then
        worker_mode=''${FIREBREAK_WORKER_MODE:-}
      fi
      if [ -z "$worker_mode" ] && [ -r /run/firebreak-worker/worker-mode ]; then
        worker_mode=$(cat /run/firebreak-worker/worker-mode)
      fi
      worker_mode=$(normalize_worker_mode "$worker_mode")
      if [ -z "$worker_mode" ] && [ -n "$proxy_default_mode" ]; then
        worker_mode=$proxy_default_mode
        worker_mode=$(normalize_worker_mode "$worker_mode")
      fi
      if [ -z "$worker_mode" ]; then
        worker_mode=$default_worker_mode
        worker_mode=$(normalize_worker_mode "$worker_mode")
      fi

      if [ "''${FIREBREAK_WRAPPER_INFO:-}" = "1" ]; then
        cat <<__FIREBREAK_WRAPPER_INFO__
{
  "wrapper": "firebreak",
  "command": "$(json_escape ${lib.escapeShellArg commandName})",
  "kind": "$(json_escape ${lib.escapeShellArg kind})",
  "default_mode": "$(json_escape "$default_worker_mode")",
  "resolved_mode": "$(json_escape "$worker_mode")",
  "upstream_bin": "$(json_escape "$upstream_bin")"
}
__FIREBREAK_WRAPPER_INFO__
        exit 0
      fi

      case "$worker_mode" in
        vm)
          ;;
        local)
          if ! [ -x "$upstream_bin" ]; then
            echo "missing upstream binary for ${commandName}: $upstream_bin" >&2
            exit 1
          fi
          exec "$upstream_bin" "$@"
          ;;
        *)
          echo "unsupported FIREBREAK_WORKER_MODE: $worker_mode" >&2
          echo "supported values: vm, local" >&2
          exit 1
          ;;
      esac

      workspace=$PWD
      if worker_command_needs_attach "$@"; then
        exec firebreak worker run --kind ${lib.escapeShellArg kind} --workspace "$workspace" --attach -- "$@"
      fi
      exec firebreak worker run --kind ${lib.escapeShellArg kind} --workspace "$workspace" -- "$@"
    '';

  mkWorkspaceProjectArtifacts = {
    name,
    displayName,
    tagline,
    repoMarkers,
    lockfiles ? [ ],
    runtimePackages,
    bootstrapPackages ? null,
    bootstrapCommands,
    launchCommand,
    readyCommands ? [ ],
    extraShellInit ? "",
    extraModules ? [ ],
    workerBridgeEnabled ? false,
    workerKinds ? { },
  }:
    let
      packageSet =
        if builtins.isFunction runtimePackages then
          runtimePackages
        else
          (_: runtimePackages);

      bootstrapPackageSet =
        if bootstrapPackages == null then
          packageSet
        else if builtins.isFunction bootstrapPackages then
          bootstrapPackages
        else
          (_: bootstrapPackages);

      repoMarkerArgs = lib.escapeShellArgs repoMarkers;
      lockfileArgs = lib.escapeShellArgs lockfiles;
      readyCommandArgs = lib.escapeShellArgs readyCommands;
      readyCommandName = "${name}-ready";
      effectiveWorkerBridgeEnabled = workerBridgeEnabled || workerKinds != { };
      launchCommandName = "${name}-launch";
    in
    mkLocalVmArtifacts {
      inherit name;
      defaultAgentCommand = launchCommandName;
      workerBridgeEnabled = effectiveWorkerBridgeEnabled;
      inherit workerKinds;
      extraModules = [
        ({ config, pkgs, ... }:
          let
            cfg = config.workloadVm;
            devHome = cfg.devHome;
            stateRoot = "${devHome}/.cache/firebreak-workspaces/${name}";
            workspaceOwnedPaths = [
              stateRoot
              "${devHome}/.cache/tmp"
              "${devHome}/.config"
              "${devHome}/.local/bin"
              "${devHome}/.local/share/pnpm"
              "${devHome}/.local/state"
              "${devHome}/.cargo"
              "${devHome}/.rustup"
            ];
            workspaceOwnedPathLines = lib.concatStringsSep " \\\n  " (map lib.escapeShellArg workspaceOwnedPaths);
            tools = packageSet pkgs;
            bootstrapTools = bootstrapPackageSet pkgs;
            sharedBootstrapPackages = with pkgs; [
              coreutils
              gnugrep
              gnused
              util-linux
            ];
            launchCommandScript = pkgs.writeShellScript "${name}-workspace-launch-command" ''
              set -eu
              cd "$1"
              ${launchCommand}
            '';
            bootstrapCommandScript = pkgs.writeShellScript "${name}-workspace-bootstrap-command" ''
              set -eu
              mkdir -p \
                "$XDG_CONFIG_HOME" \
                "$XDG_CACHE_HOME/tmp" \
                "$XDG_STATE_HOME" \
                "$HOME/.local/bin" \
                "$PNPM_HOME" \
                "$CARGO_HOME" \
                "$RUSTUP_HOME"
              cd "$WORKSPACE"
              ${bootstrapCommands}
            '';
            bootstrapConditionScript = pkgs.writeShellScript "${name}-workspace-bootstrap-condition" ''
              set -eu

              # This script is used as a systemd ExecCondition for bootstrap.
              # Exit 0 means "proceed with service start"; non-zero means "skip".
              # The condition intentionally exits 1 when repo markers are missing
              # or when current_hash already matches state_file.
              workspace="${cfg.workspaceMount}"
              state_file="${stateRoot}/inputs.sha256"
              missing_marker=""

              for marker in ${repoMarkerArgs}; do
                if ! [ -e "$workspace/$marker" ]; then
                  missing_marker=$marker
                  break
                fi
              done

              if [ -n "$missing_marker" ]; then
                exit 1
              fi

              hash_input=$(mktemp)
              {
                for lockfile in ${lockfileArgs}; do
                  if [ -e "$workspace/$lockfile" ]; then
                    sha256sum "$workspace/$lockfile"
                  fi
                done
              } > "$hash_input"

              if [ -s "$hash_input" ]; then
                current_hash=$(sha256sum "$hash_input" | cut -d' ' -f1)
              else
                current_hash=no-lockfiles
              fi
              rm -f "$hash_input"

              if [ -r "$state_file" ] && [ "$(cat "$state_file")" = "$current_hash" ]; then
                exit 1
              fi

              exit 0
            '';
            readyScript = pkgs.writeShellApplication {
              name = readyCommandName;
              runtimeInputs = with pkgs; [ coreutils ];
              text = ''
                set -eu

                workspace="${cfg.workspaceMount}"
                missing_marker=""

                for marker in ${repoMarkerArgs}; do
                  if ! [ -e "$workspace/$marker" ]; then
                    missing_marker=$marker
                    break
                  fi
                done

                printf '\n%s sandbox ready.\n' '${displayName}'
                printf 'workspace: %s\n' "$workspace"

                if [ -n "$missing_marker" ]; then
                  printf 'repo root check: missing %s\n' "$missing_marker"
                  printf 'launch this recipe from the target project root to enable automatic preparation.\n\n'
                  exit 0
                fi

                if [ -d "$workspace/node_modules" ]; then
                  printf 'node dependencies: prepared\n'
                fi

                if [ -f "$workspace/Cargo.lock" ]; then
                  printf 'rust lockfile: present\n'
                fi

                printf 'manual refresh: firebreak-prepare-workspace\n'
                printf 'quick commands:\n'
                for command in ${readyCommandArgs}; do
                  printf '  %s\n' "$command"
                done
                printf '\n'
              '';
            };
            launchScript = pkgs.writeShellApplication {
              name = launchCommandName;
              runtimeInputs = with pkgs; [ coreutils ];
              text = ''
                set -eu

                workspace="${cfg.workspaceMount}"
                missing_marker=""

                for marker in ${repoMarkerArgs}; do
                  if ! [ -e "$workspace/$marker" ]; then
                    missing_marker=$marker
                    break
                  fi
                done

                if [ -n "$missing_marker" ]; then
                  printf 'Cannot launch %s: missing repo root marker %s\n' '${displayName}' "$missing_marker" >&2
                  printf 'Run this recipe from the target project root, or use shell mode for manual recovery.\n' >&2
                  exit 1
                fi

                exec ${launchCommandScript} "$workspace"
              '';
            };
          in {
            workloadVm = {
              brandingTagline = tagline;
              environmentOverlay = {
                enable = true;
                package.packages = tools;
                projectNix.enable = true;
              };
              extraSystemPackages = [ launchScript readyScript ];
              bootstrapPackages = sharedBootstrapPackages ++ bootstrapTools;
              bootstrapConditionScript = "${bootstrapConditionScript}";
              bootstrapScript = ''
                set -eu

                workspace="${cfg.workspaceMount}"
                dev_home="${devHome}"
                dev_user="${cfg.devUser}"
                state_root="${stateRoot}"
                state_file="$state_root/inputs.sha256"
                missing_marker=""

                for marker in ${repoMarkerArgs}; do
                  if ! [ -e "$workspace/$marker" ]; then
                    missing_marker=$marker
                    break
                  fi
                done

                if [ -n "$missing_marker" ]; then
                  printf '%s\n' "${displayName}: skipping dependency preparation; expected repo root marker missing: $missing_marker"
                  exit 0
                fi

                mkdir -p \
                  ${workspaceOwnedPathLines}

                hash_input=$(mktemp)
                {
                  for lockfile in ${lockfileArgs}; do
                    if [ -e "$workspace/$lockfile" ]; then
                      sha256sum "$workspace/$lockfile"
                    fi
                  done
                } > "$hash_input"

                if [ -s "$hash_input" ]; then
                  current_hash=$(sha256sum "$hash_input" | cut -d' ' -f1)
                else
                  current_hash=no-lockfiles
                fi
                rm -f "$hash_input"

                if [ -r "$state_file" ] && [ "$(cat "$state_file")" = "$current_hash" ]; then
                  printf '%s\n' '${displayName}: dependency preparation already matches the workspace inputs.'
                  exit 0
                fi

                chown -R "$dev_user:$dev_user" \
                  ${workspaceOwnedPathLines}

                runuser -u "$dev_user" -- env \
                  HOME="$dev_home" \
                  XDG_CONFIG_HOME="$dev_home/.config" \
                  XDG_CACHE_HOME="$dev_home/.cache" \
                  XDG_STATE_HOME="$dev_home/.local/state" \
                  TMPDIR="$dev_home/.cache/tmp" \
                  PNPM_HOME="$dev_home/.local/share/pnpm" \
                  CARGO_HOME="$dev_home/.cargo" \
                  RUSTUP_HOME="$dev_home/.rustup" \
                  WORKSPACE="$workspace" \
                  PATH="$dev_home/.local/share/pnpm:$dev_home/.local/bin:$dev_home/.cargo/bin:$PATH" \
                  ${bootstrapCommandScript}

                printf '%s\n' "$current_hash" > "$state_file"
                chown -R "$dev_user:$dev_user" \
                  ${workspaceOwnedPathLines}
                printf '%s\n' '${displayName}: dependency preparation finished.'
              '';
              shellInit = ''
                export FIREBREAK_EXTERNAL_PROJECT="${name}"
                export PNPM_HOME="${devHome}/.local/share/pnpm"
                export CARGO_HOME="${devHome}/.cargo"
                export RUSTUP_HOME="${devHome}/.rustup"
                export PATH="$PNPM_HOME:$HOME/.local/bin:$CARGO_HOME/bin:$PATH"

                alias project-launch='${launchCommandName}'
                alias project-ready='${readyCommandName}'
                alias firebreak-prepare-workspace='sudo systemctl restart dev-bootstrap.service && project-ready'
                ${extraShellInit}
              '';
            };
          })
      ] ++ extraModules;
    };

  mkPackagedNodeCliArtifacts = {
    name,
    displayName,
    tagline,
    packageSpec,
    binName,
    launchCommand ? binName,
    launchEnvironment ? { },
    forwardPorts ? [ ],
    postInstallScript ? "",
    installBinScripts ? { },
    memoryMiB ? 3072,
    runtimePackages ? [ ],
    bootstrapPackages ? null,
    sharedStateRoots ? { },
    sharedCredentialSlots ? { },
    extraShellInit ? "",
    extraModules ? [ ],
    workerBridgeEnabled ? false,
    defaultWorkerMode ? "local",
    workerKinds ? { },
    workerProxies ? { },
  }:
    let
      derivedProxyLocalUpstreams =
        lib.mapAttrs
          (commandName: proxy:
            let
              packageName = proxy.package or null;
              knownUpstream =
                if packageName != null && builtins.hasAttr packageName workerProxyLocalUpstreamsByPackage
                then builtins.getAttr packageName workerProxyLocalUpstreamsByPackage
                else { };
              upstreamBinName = knownUpstream.binName or commandName;
            in
            lib.filterAttrs (_: value: value != null) {
              packageSpec = knownUpstream.packageSpec or null;
              binName = upstreamBinName;
              package = knownUpstream.package or null;
              realBinPath =
                if knownUpstream ? package
                then "${knownUpstream.package}/bin/${upstreamBinName}"
                else null;
            })
          workerProxies;

      derivedWorkerKinds =
        lib.mapAttrs'
          (_commandName: proxy:
            lib.nameValuePair proxy.kind (builtins.removeAttrs proxy [ "kind" "versionOutput" ]))
          workerProxies;

      derivedInstallBinScripts =
        lib.mapAttrs
          (commandName: proxy:
            mkWorkerProxyScript {
              inherit commandName;
              kind = proxy.kind;
              defaultMode = proxy.defaultMode or null;
              inherit defaultWorkerMode;
            })
          workerProxies;

      effectiveWorkerKinds = derivedWorkerKinds // workerKinds;
      effectiveInstallBinScripts = derivedInstallBinScripts // installBinScripts;
      effectiveWorkerBridgeEnabled = workerBridgeEnabled || workerKinds != { } || workerProxies != { };
      installBinSystemPackages =
        lib.mapAttrsToList
          (scriptName: scriptText: pkgs.writeShellScriptBin scriptName scriptText)
          effectiveInstallBinScripts;

      packageSet =
        if builtins.isFunction runtimePackages then
          runtimePackages
        else
          (_: runtimePackages);

      bootstrapPackageSet =
        if bootstrapPackages == null then
          packageSet
        else if builtins.isFunction bootstrapPackages then
          bootstrapPackages
        else
          (_: bootstrapPackages);

      readyCommandName = "${name}-ready";
      launchCommandName = "${name}-launch";
    in
    mkLocalVmArtifacts {
      inherit name;
      defaultAgentCommand = launchCommandName;
      inherit sharedStateRoots sharedCredentialSlots;
      workerBridgeEnabled = effectiveWorkerBridgeEnabled;
      workerKinds = effectiveWorkerKinds;
      extraModules = [
        (import ../../modules/node-cli/module.nix {
          inherit
            displayName
            tagline
            packageSpec
            binName
            launchCommand
            launchCommandName
            launchEnvironment
            forwardPorts
            postInstallScript
            readyCommandName
            memoryMiB
            sharedStateRoots
            sharedCredentialSlots
            extraShellInit
            ;
          installBinScripts = effectiveInstallBinScripts;
          proxyLocalUpstreams = derivedProxyLocalUpstreams;
          vmName = name;
          extraSystemPackages = installBinSystemPackages;
          extraBootstrapPackages = bootstrapPackageSet pkgs;
        })
        ({ ... }: {
          workloadVm.environmentOverlay.package.packages = packageSet pkgs;
        })
      ] ++ extraModules;
    };

  mkPackagedNodeCliFlakeOutputs = {
    firebreak,
    nixpkgs,
    mkProject,
    testsModule,
    nixosConfigurationName,
    packageName,
    runnerPackageName,
    defaultForwardPorts ? [ ],
    defaultSystem ? null,
  }:
    let
      supportedSystems = builtins.attrNames firebreak.lib;
      effectiveDefaultSystem =
        if defaultSystem != null then
          defaultSystem
        else
          "x86_64-linux";
      projectFor = system: mkProject system defaultForwardPorts;
      testProjectFor = system: mkProject system [ ];
      testsFor = system:
        import testsModule {
          pkgs = import nixpkgs {
            inherit system;
            config = import ./nixpkgs-config.nix {
              inherit lib;
            };
          };
          project = projectFor system;
          testProject = testProjectFor system;
          firebreakBin = "${firebreak.packages.${system}.default}/bin/firebreak";
        };
      defaultProject = projectFor effectiveDefaultSystem;
    in {
      nixosConfigurations.${nixosConfigurationName} = defaultProject.nixosConfiguration;

      packages = lib.genAttrs supportedSystems (system:
        let
          project = projectFor system;
          tests = testsFor system;
        in tests.packages // {
          default = project.package;
          "${packageName}" = project.package;
          "${runnerPackageName}" = project.runnerPackage;
        });
      checks = lib.genAttrs supportedSystems (system:
        let
          tests = testsFor system;
        in
        tests.packages // tests.checks);
    };
}
