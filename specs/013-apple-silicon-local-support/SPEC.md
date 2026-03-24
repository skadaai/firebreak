---
status: draft
last_updated: 2026-03-24
---

# 013 Apple Silicon Local Support

## Problem

Firebreak's local VM surface now covers Linux hosts, but it still does not support local interactive use on Apple Silicon Macs.

That leaves one high-value local use case unresolved:

- an operator on an `aarch64-darwin` host wants to run Firebreak locally for interactive agent use

The existing Linux local runtime is not directly reusable for that case because it is built around Linux host assumptions such as KVM readiness checks, QEMU-specific runtime wiring, and `9p`-based host metadata sharing.

At the same time, Firebreak does not need a generic runtime-profile selection feature to solve this problem. The product need is a narrow host-platform extension for local use on Apple Silicon.

## Affected users, actors, or systems

- operators using Apple Silicon Macs for local interactive Firebreak workloads
- maintainers evolving Firebreak's local host-platform contract
- launcher, diagnostics, and local runtime code that currently assume Linux host semantics
- future validation environments for Apple Silicon local support

## Goals

- support Firebreak local interactive workloads on `aarch64-darwin`
- keep the supported guest architecture for this host path as `aarch64-linux`
- use `vfkit` as the Apple Silicon local runtime
- keep the public local workload names and CLI entrypoints unchanged
- preserve the current Linux local experience while adding a host-specific macOS local path
- land a minimum viable first launch path for Apple Silicon local use before broader refinement

## Non-goals

- Intel Mac support
- cloud support for macOS
- generic user-selectable runtime profiles
- exposing hypervisor choice as a public product surface
- redesigning Linux local support around multiple runtime options
- changing the public workload names such as `firebreak-codex` or `firebreak-claude-code`

## Morphology and scope of the changeset

This changeset is behavioral, structural, and operational.

It adds a dedicated Apple Silicon local host path rather than a generic profile matrix.

The intended landing shape is:

- Firebreak exports host-side packages for `aarch64-darwin`
- Apple Silicon local launch uses a dedicated `vfkit`-based runtime path
- the Apple Silicon local path uses `aarch64-linux` guests
- local share and readiness behavior are adapted to macOS host constraints rather than Linux KVM assumptions
- Linux local support remains QEMU-first and unchanged as a public contract

## Requirements

- The system shall support Firebreak local workload packages on `aarch64-darwin`.
- The system shall use `aarch64-linux` guests for Apple Silicon local workloads.
- The system shall use `vfkit` as the Apple Silicon local runtime.
- The system shall keep Apple Silicon local support limited to local workloads for this changeset.
- The system shall not expose user-selectable runtime-profile choice as part of Apple Silicon local support.
- The system shall keep the existing public local workload names and CLI entrypoints unchanged.
- The system shall preserve the existing Linux local public contract while adding a separate Apple Silicon local runtime path.
- When Firebreak runs on Apple Silicon, the system shall use host-readiness checks that match the macOS local runtime instead of Linux `/dev/kvm` checks.
- The system shall use share semantics for Apple Silicon local support that are compatible with `vfkit`.
- The system shall provide a minimum viable first launch path that supports interactive local launch, shell mode, workspace sharing, agent config sharing, and one-shot agent command execution on Apple Silicon.
- If Firebreak is launched on `x86_64-darwin`, then the system shall fail clearly because Intel Mac support is out of scope.
- If Firebreak is launched on macOS for cloud execution paths, then the system shall fail clearly because cloud macOS support is out of scope.

## Acceptance criteria

- `nix run .#firebreak-codex` and `nix run .#firebreak-claude-code` evaluate for `aarch64-darwin`.
- on an Apple Silicon Mac, `nix run .#firebreak-codex` reaches the local agent entry path through a `vfkit`-based runtime.
- on an Apple Silicon Mac, `FIREBREAK_VM_MODE=shell nix run .#firebreak-codex` reaches the maintenance shell.
- on an Apple Silicon Mac, the local workspace path is shared into the guest and remains usable for interactive work.
- on an Apple Silicon Mac, the local agent config path is shared into the guest when the selected config mode requires it.
- on an Apple Silicon Mac, one-shot agent command execution still works for a simple command such as `--version`.
- launcher and diagnostics behavior distinguish Apple Silicon local readiness from Linux KVM readiness.
- Linux local documentation and behavior continue to describe one QEMU-backed Linux local path rather than a generalized runtime-selection surface.
- unsupported Darwin cases such as `x86_64-darwin` fail clearly.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 012](../012-linux-multi-arch-host-support/SPEC.md)
- current [flake.nix](../../flake.nix)
- current local runtime files under [modules/profiles/local/](../../modules/profiles/local/)
- current VM base under [modules/base/](../../modules/base/)

### Risks

- the existing local runtime may need deeper refactoring than expected because it still embeds QEMU- and Linux-specific assumptions
- Apple Silicon local share behavior may require a clearer contract for host metadata transport than the current Linux-specific `9p` path
- host and guest architecture alignment for `vfkit` may force broader guest-architecture awareness than the current Linux local path needs
- partial support that boots but does not preserve workspace, config, or one-shot command behavior would create a misleading product contract

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
- [UPSTREAM_REPOS.md](../../UPSTREAM_REPOS.md)
