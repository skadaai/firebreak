{ lib, pkgs, renderTemplate, mkLocalVmArtifacts }:
{
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
      extraModules = [
        ({ config, pkgs, ... }:
          let
            cfg = config.agentVm;
            devHome = "/var/lib/${cfg.devUser}";
            tools = packageSet pkgs;
            bootstrapTools = bootstrapPackageSet pkgs;
            sharedBootstrapPackages = with pkgs; [
              coreutils
              gnugrep
              gnused
              util-linux
            ];
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

                exec bash -lc '
                  set -eu
                  cd "$1"
                  ${launchCommand}
                ' bash "$workspace"
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
                state_root="$dev_home/.cache/firebreak-workspaces/${name}"
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
                  "$state_root" \
                  "$dev_home/.cache/tmp" \
                  "$dev_home/.config" \
                  "$dev_home/.local/bin" \
                  "$dev_home/.local/share/pnpm" \
                  "$dev_home/.local/state" \
                  "$dev_home/.cargo" \
                  "$dev_home/.rustup"
                chown -R "$dev_user:$dev_user" "$dev_home"

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
                  sh -lc '
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
                  '

                printf '%s\n' "$current_hash" > "$state_file"
                chown -R "$dev_user:$dev_user" "$state_root" "$dev_home"
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
    memoryMiB ? 3072,
    runtimePackages ? [ ],
    bootstrapPackages ? null,
    extraShellInit ? "",
    extraModules ? [ ],
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
            extraShellInit
            ;
          vmName = name;
          extraSystemPackages = packageSet pkgs;
          extraBootstrapPackages = bootstrapPackageSet pkgs;
        })
      ] ++ extraModules;
    };
}
