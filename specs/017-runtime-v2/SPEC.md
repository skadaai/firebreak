---
status: draft
last_updated: 2026-04-05
---

# 017 Runtime V2

## Problem

Firebreak's current local runtime is too slow to compete with containers or feel usable as a primary developer surface.

The current architecture couples Firebreak's product behavior to one experimental QEMU-first implementation shape:

- Linux local launch defaults to QEMU
- Linux local boot still depends on slow host-share and guest-boot paths
- local worker isolation is modeled as more VM launches rather than near-immediate prepared-instance starts
- port publishing relies on QEMU-specific user networking behavior
- runtime evolution risks turning into a matrix of partially supported hypervisor paths

That is the wrong center of gravity for the product.

Firebreak is meant to be a system-isolation product with container-like ergonomics, not a long-lived compatibility layer around one hypervisor experiment.

## Affected users, actors, or systems

- humans launching local Firebreak workloads for coding agents and orchestrators
- maintainers evolving Firebreak's local and cloud runtime contracts
- host-side runtime assembly, networking, and mount plumbing
- future cloud deployment work under `firebreak deploy`
- validation and CI surfaces that currently inherit QEMU-first assumptions

## Goals

- redefine Firebreak around product profiles rather than around one hypervisor implementation
- make local Firebreak startup fast enough to be competitive for repeated developer use
- keep the local product centered on fast isolated MicroVM launch with live workspace access
- define a future cloud runtime shape without forcing cloud constraints onto the local path
- keep the public support matrix small and explicit
- fail early when a backend cannot satisfy the required capabilities of a profile
- replace inferior runtime paths aggressively instead of carrying compatibility layers

## Non-goals

- preserving Linux local QEMU as a long-term compatibility mode
- exposing hypervisor choice as a public end-user surface
- supporting every profile on every backend
- graceful degradation between different isolation, mount, console, networking, or snapshot semantics
- keeping migration-only shims once the replacement runtime path is accepted
- solving every cloud backend detail in the same changeset

## Morphology and scope of the changeset

This changeset is structural and operational.

It reframes Firebreak around a stable product contract with backend-specific implementations hidden underneath.

The intended landing shape is:

- Firebreak keeps product profiles such as `local` and `cloud`
- Firebreak adds private runtime backends beneath those profiles
- each supported profile-platform combination maps to one supported backend
- Linux local Firebreak uses Cloud Hypervisor instead of QEMU
- Apple Silicon local Firebreak continues using `vfkit`
- future cloud Firebreak may use a different backend such as Firecracker without changing the local profile contract
- unsupported profile-backend combinations fail early instead of degrading silently
- once Linux local Cloud Hypervisor is accepted, the Linux local QEMU path is removed rather than kept as a compatibility layer

## Runtime model

### Product profiles

- `local`: interactive developer-oriented runtime with live workspace access, interactive console semantics, and host-facing port publishing
- `cloud`: deploy-oriented runtime with image and volume semantics suitable for remote execution and later snapshot-driven scaling

### Runtime backends

Runtime backends are implementation details owned under shared runtime support code rather than exposed as public profiles.

Backends shall provide a narrow capability contract to profiles.

### Supported matrix

The supported matrix shall stay intentionally small:

- local on Linux shall use Cloud Hypervisor
- local on Apple Silicon macOS shall use `vfkit`
- cloud shall use a cloud-oriented backend when that profile lands

The system shall not keep a second first-class Linux local backend once the replacement path is accepted.

## Module boundaries

- `modules/base` shall keep the shared guest contract, state semantics, credential semantics, shell/bootstrap contract, and worker semantics.
- `modules/profiles/local` shall keep local-only product behavior such as workspace access, local console expectations, host-facing port publishing, and local preparation semantics.
- `modules/profiles/cloud` shall keep cloud-only product behavior such as image-oriented execution, volume ownership, deploy semantics, and cloud job lifecycle.
- backend-specific hypervisor invocation, share plumbing, networking implementation, snapshot plumbing, and control-plane wiring shall live under shared runtime support code rather than under profile directories.
- profiles shall depend on backend capabilities, not on backend-specific command-line details.

## Capability contract

The system shall define profile requirements in capability terms rather than as backend names.

At minimum, Firebreak shall model capabilities for:

- interactive console
- workspace sharing
- writable volume attachment
- host-facing port publishing
- control socket or equivalent runtime control path
- snapshot support
- `vsock` support

If a backend cannot satisfy a profile's required capabilities, then the system shall fail early and clearly.

The system shall not silently fall back to different networking, mount, console, or isolation semantics.

## Requirements

- The system shall preserve `local` and `cloud` as product profiles rather than multiplying public profile names per backend.
- The system shall keep runtime backends as implementation details beneath the product profiles.
- The system shall define a narrow backend capability contract consumed by product profiles.
- The system shall allow each profile-platform combination to select one supported backend.
- The system shall not require every backend to satisfy every profile.
- If a backend cannot satisfy a profile's required capabilities, then the system shall fail early and clearly.
- The system shall not implement graceful degradation across materially different runtime semantics.
- The system shall not keep compatibility layers solely to preserve an inferior superseded runtime path.
- When Linux local Cloud Hypervisor is accepted as the replacement runtime, the system shall remove the Linux local QEMU path rather than carrying both as first-class options.
- The system shall prefer direct replacement and deletion over rollout-oriented coexistence when the superseded runtime path is experimental and materially worse.
- The system shall keep Apple Silicon local support on `vfkit` until a better supported replacement satisfies the local profile capability contract on that platform.
- The system shall keep the public Firebreak local user experience focused on fast isolated system launch with live workspace access.
- The system shall support host-facing local port publishing without requiring users to learn backend-specific networking terms.
- The system shall support local workspace access without forcing cloud-style image-only semantics onto the local profile.
- The system shall define the future cloud profile in terms of image, volume, and snapshot-oriented behavior rather than live host workspace mounts.
- The system shall allow the cloud profile to use a different backend than the local profile without multiplying public profile names.
- The system shall keep the supported profile-backend-platform matrix intentionally small and explicitly documented.
- The system shall prefer deleting superseded runtime code over preserving rollout-oriented compatibility branches once the replacement path lands.

## Acceptance criteria

- Firebreak's public runtime surface is described in terms of `local` and `cloud` profiles rather than backend names.
- backend-specific logic is structurally separated from product-profile logic.
- Linux local runtime support is defined around one primary backend rather than multiple first-class alternatives.
- unsupported backend/profile combinations fail explicitly instead of degrading to a weaker behavior.
- Linux local port publishing remains available to users without exposing backend-specific networking configuration as part of the public contract.
- the repository no longer treats preserving Linux local QEMU compatibility as a design goal once the replacement runtime path is adopted.
- the repository treats aggressive deletion of the superseded Linux local runtime as the default landing shape rather than as an optional cleanup.
- the repository documents a small explicit support matrix rather than an open-ended hypervisor/profile matrix.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- current runtime assembly under [nix/support/runtime.nix](../../nix/support/runtime.nix)
- current VM base under [modules/base/](../../modules/base/)
- current local profile under [modules/profiles/local/](../../modules/profiles/local/)
- current cloud profile under [modules/profiles/cloud/](../../modules/profiles/cloud/)

### Risks

- backend-capability boundaries could be defined too loosely and allow backend-specific assumptions to leak back into product profiles
- Linux local port publishing could become more complex to implement under Cloud Hypervisor than under QEMU user networking
- retaining too much QEMU-specific structure during replacement could recreate the same complexity under a different name
- moving too much local behavior into backend code could blur the product contract between local and cloud profiles

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
- [UPSTREAM_REPOS.md](../../UPSTREAM_REPOS.md)
