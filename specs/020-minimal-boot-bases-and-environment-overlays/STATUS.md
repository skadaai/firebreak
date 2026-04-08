---
status: active
last_updated: 2026-04-07
---

# 020 Minimal Boot Bases And Environment Overlays Status

## Current phase

Environment overlay implementation plus boot-base split.

## What is landed already

- Firebreak shares the host `/nix/store` by default on the local Cloud Hypervisor path
- package-specific behavior is already modeled as thin overlay modules rather than as distinct full guest images
- packaged Node CLIs now use a persistent tool-runtime directory
- local tool bootstrap has been moved off the shell critical path
- local packaged Node CLI tool bootstrap now begins on the host and overlaps with guest boot
- Firebreak now has a formal additive environment-overlay contract in the shared VM options
- Firebreak CLI and `firebreak doctor` can resolve and inspect environment identities and cache paths
- Firebreak can materialize a cached environment overlay from explicit installables or constrained project-local flake defaults
- local wrappers can export resolved environment overlays into the guest through host metadata
- workspace-style project artifacts now opt into constrained project-local flake environment resolution
- local runtimes now select explicit `command` and `interactive` boot bases through the shared runtime contract instead of ad hoc wrapper logic
- local interactive services now boot under `firebreak-interactive.target`, while one-shot command execution continues to use `firebreak-cold-exec.target`
- local environment resolution and materialization now run in the background so that host environment work can overlap with guest boot, with the guest waiting only when it actually needs the resolved overlay
- package overlays can now declare Nix installables directly, and those installables participate in the environment identity, cache materialization, and doctor/smoke coverage
- recipe-owned runtime tool packages for workspace and packaged Node CLI sandboxes now resolve through environment overlay path prefixes instead of being baked into the guest image
- packaged-agent helper tools can now come from environment overlay path prefixes on the command path, so helper binaries like `ripgrep` no longer need to inflate the guest image
- packaged Node CLI runtimes now enable their environment overlay by default and export `nodejs_20` through that overlay instead of baking Node into the guest image
- project-local Nix auto-detection now explicitly accepts `devShells.<system>.default`, `packages.<system>.default`, and `legacyPackages.<system>.default`, and fails fast when a workspace opts in but does not expose one of those supported defaults
- project-local Nix auto-detection now also accepts constrained `shell.nix` and `default.nix` development environments using the pinned Firebreak `nixpkgs` input instead of ambient host `NIX_PATH`
- the local Cloud Hypervisor boot base now strips more generic NixOS login and name-resolution machinery from the common path, including `resolvconf`, `nscd`, `logind`, `systemd-user-sessions`, `lastlog2-import`, and `getty.target`
- the local Cloud Hypervisor boot base now disables D-Bus and the hostnamed/localed/timedated services that sit outside Firebreak's hot path
- the local Cloud Hypervisor boot base now also disables the matching hostnamed/localed/timedated socket units, closing the remaining socket-activation regression on the Claude local path
- package-owned overlay dependencies can now be declared as Nix package objects and normalized into overlay path prefixes by the shared base module, removing more ad hoc per-module `\"${pkg}/bin\"` wiring

## What remains open

- a dedicated public cache layer for high-ROI outer build/substitution reduction, now tracked in [specs/021-public-cache-layer/SPEC.md](../021-public-cache-layer/SPEC.md)
- continuing the package-default environment model beyond the initial overlay contract
- continuing the kernel/initrd and guest service-graph reduction against those bases
