---
status: draft
last_updated: 2026-03-24
---

# 012 Linux Multi-Arch Host Support

## Problem

Firebreak's local VM surface currently assumes a single host platform: `x86_64-linux`.

That assumption is embedded in:

- top-level flake output assembly
- launcher preflight checks
- runner patching for QEMU CPU and KVM behavior
- validation and diagnostics wording
- repository documentation and CI expectations

This makes Firebreak unavailable on Linux hosts that can plausibly run the same local VM workflows, most notably `aarch64-linux`.

## Affected users, actors, or systems

- maintainers evolving Firebreak's host-platform contract
- Linux users running Firebreak on ARM64 machines
- CI and validation environments for local VM workloads
- coding agents modifying flake outputs, host wrappers, and VM runtime assumptions

## Goals

- support Firebreak local workloads on both `x86_64-linux` and `aarch64-linux` hosts
- keep Linux as the required host operating system for this changeset
- preserve a Linux NixOS guest model for local workloads
- separate host-system concerns from guest-system concerns in the flake architecture
- make launcher, validation, and documentation reflect the expanded Linux host contract

## Non-goals

- native macOS host support
- native Windows host support
- introducing non-KVM local execution as a supported primary mode
- redesigning Firebreak around a hypervisor abstraction layer beyond the current QEMU-backed approach
- changing public workload names such as `firebreak-codex` or `firebreak-claude-code`

## Morphology and scope of the changeset

This changeset is structural and operational.

It expands Firebreak's local host-platform contract from a single Linux architecture to multiple Linux architectures while keeping the existing Linux guest model.

The intended landing shape is:

- flake outputs are assembled for more than one Linux host system
- host package assembly no longer assumes that host system and guest system are the same concept
- runner compatibility logic no longer embeds x86-only CPU assumptions into the generic path
- public launch and validation surfaces recognize supported Linux host architectures explicitly
- repository docs and validation guidance describe the supported Linux host matrix clearly

## Requirements

- The system shall support Firebreak local workload packages on `x86_64-linux`.
- The system shall support Firebreak local workload packages on `aarch64-linux`.
- The system shall keep Linux as the required host operating system for this changeset.
- The system shall keep a Linux NixOS guest model for local workloads.
- The system shall separate host-system package assembly from guest-system VM construction where those concerns differ.
- The system shall avoid embedding x86-specific QEMU CPU flags in the generic runner compatibility path.
- When a supported Linux host architecture lacks usable KVM access, the system shall continue to report that capability failure clearly.
- The system shall keep existing public workload names and top-level CLI entrypoints unchanged.
- The system shall update documentation to describe the supported host matrix and any host-specific validation expectations.

## Acceptance criteria

- `nix run .#firebreak-codex` and `nix run .#firebreak-claude-code` evaluate on both `x86_64-linux` and `aarch64-linux` hosts.
- flake output wiring clearly distinguishes host-system package assembly from Linux guest construction.
- generic runner patching no longer assumes x86 CPU feature flags.
- launcher preflight checks accept both `x64` and `arm64` Linux hosts and continue rejecting unsupported host operating systems.
- diagnostics and validation still identify missing KVM access as a capability issue on supported Linux hosts.
- repository docs describe `x86_64-linux` and `aarch64-linux` as supported local host targets.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- current [flake.nix](../../flake.nix)
- current [nix/flake-support.nix](../../nix/flake-support.nix)
- current [bin/firebreak.js](../../bin/firebreak.js)

### Risks

- host-system and guest-system separation could introduce flake recursion or broken output references
- host-specific runner patching could drift from upstream `microvm.nix` runner behavior
- ARM Linux support could evaluate successfully while still failing at runtime on real hardware without dedicated validation
- documentation could overstate support before CI and smoke coverage reflect the new host matrix

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
- [UPSTREAM_REPOS.md](../../UPSTREAM_REPOS.md)
