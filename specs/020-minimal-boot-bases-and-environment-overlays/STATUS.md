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

## What remains open

- continuing the package-default environment model beyond the initial overlay contract
- continuing the kernel/initrd and guest service-graph reduction against those bases
- overlapping environment resolution and materialization with guest boot where possible
