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
- project-local Nix auto-detection now explicitly accepts `devShells.<system>.default`, `packages.<system>.default`, and `legacyPackages.<system>.default`, and fails fast when a workspace opts in but does not expose one of those supported defaults
- the local Cloud Hypervisor boot base now strips more generic NixOS login and name-resolution machinery from the common path, including `resolvconf`, `nscd`, `logind`, `systemd-user-sessions`, `lastlog2-import`, and `getty.target`

## What remains open

- continuing the package-default environment model beyond the initial overlay contract
- continuing the kernel/initrd and guest service-graph reduction against those bases
