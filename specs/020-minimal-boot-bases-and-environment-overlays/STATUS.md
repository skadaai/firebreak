---
status: draft
last_updated: 2026-04-07
---

# 020 Minimal Boot Bases And Environment Overlays Status

## Current phase

Design definition.

## What is landed already

- Firebreak shares the host `/nix/store` by default on the local Cloud Hypervisor path
- package-specific behavior is already modeled as thin overlay modules rather than as distinct full guest images
- packaged Node CLIs now use a persistent tool-runtime directory
- local tool bootstrap has been moved off the shell critical path
- local packaged Node CLI tool bootstrap now begins on the host and overlaps with guest boot

## What remains open

- defining the formal environment overlay contract
- defining the environment identity and cache layout
- supporting project-local Nix declarations explicitly
- splitting Firebreak into smaller `command` and `interactive` boot bases
- continuing the kernel/initrd and guest service-graph reduction against those bases
