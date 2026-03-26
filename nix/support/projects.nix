{ lib, pkgs, renderTemplate, mkLocalVmArtifacts }:
{
  mkWorkerProxyScript =
    {
      kind,
      versionOutput ? "${kind} firebreak worker proxy",
    }:
    ''
      #!/usr/bin/env bash
      set -eu

      if [ "''${1:-}" = "--version" ]; then
        printf '%s\n' ${lib.escapeShellArg versionOutput}
        exit 0
      fi

      workspace=$PWD
      run_output=$(firebreak worker run --kind ${lib.escapeShellArg kind} --workspace "$workspace" --json -- "$@")
      printf '%s\n' "$run_output"

      worker_id=$(RUN_OUTPUT="$run_output" node -e 'process.stdout.write(JSON.parse(process.env.RUN_OUTPUT).worker_id)')
      if [ -z "$worker_id" ]; then
        echo "failed to extract Firebreak worker id from run output" >&2
        exit 1
      fi

      cleanup() {
        firebreak worker stop "$worker_id" >/dev/null 2>&1 || true
      }

      trap cleanup INT TERM

      last_status=""
      for _ in $(seq 1 3600); do
        inspect_output=$(firebreak worker inspect "$worker_id")
        status=$(INSPECT_OUTPUT="$inspect_output" node -e 'const data = JSON.parse(process.env.INSPECT_OUTPUT); process.stdout.write(String(data.status ?? ""));')

        if [ "$status" != "$last_status" ]; then
          printf '%s\n' "firebreak worker $worker_id status: $status"
          last_status=$status
        fi

        case "$status" in
          exited|stopped)
            exit_code=$(INSPECT_OUTPUT="$inspect_output" node -e 'const data = JSON.parse(process.env.INSPECT_OUTPUT); const value = data.exit_code; process.stdout.write(value === null || value === undefined ? "" : String(value));')
            exit "''${exit_code:-0}"
            ;;
        esac

        sleep 1
      done

      echo "timed out waiting for Firebreak worker $worker_id to finish" >&2
      exit 124
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
      launchCommandName = "${name}-launch";
    in
    mkLocalVmArtifacts {
      inherit name;
      defaultAgentCommand = launchCommandName;
      inherit workerBridgeEnabled;
      inherit workerKinds;
      extraModules = [
        ({ config, pkgs, ... }:
          let
            cfg = config.agentVm;
            devHome = "/var/lib/${cfg.devUser}";
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
            agentVm = {
              brandingTagline = tagline;
              agentConfigEnabled = false;
              extraSystemPackages = tools ++ [ launchScript readyScript ];
              bootstrapPackages = sharedBootstrapPackages ++ bootstrapTools;
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

      readyCommandName = "${name}-ready";
      launchCommandName = "${name}-launch";
    in
    mkLocalVmArtifacts {
      inherit name;
      defaultAgentCommand = launchCommandName;
      inherit workerBridgeEnabled;
      inherit workerKinds;
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
            installBinScripts
            readyCommandName
            memoryMiB
            extraShellInit
            ;
          vmName = name;
          extraSystemPackages = packageSet pkgs;
          extraBootstrapPackages = bootstrapPackageSet pkgs;
        })
      ] ++ extraModules;
    };
}
