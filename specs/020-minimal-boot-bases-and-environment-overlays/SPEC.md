---
status: draft
last_updated: 2026-04-07
---

# 020 Minimal Boot Bases And Environment Overlays

## Problem

Firebreak now has a better local runtime shape, but cold-start performance is still dominated by booting a fairly generic NixOS guest.

At the same time, Firebreak is intended to support an open ecosystem of packaged tools and project-local development environments. That means the product cannot scale by baking one bespoke full guest image per package.

The product needs both:

- a much smaller and faster boot base
- a much more flexible way to tailor tool and project dependencies

Those two goals are compatible only if Firebreak separates "boot the VM" from "resolve the environment".

## Goals

- keep the boot-critical VM base as small and stable as possible
- support broad customization through package-declared and project-declared Nix dependencies
- avoid tying customization to per-package full guest image rebuilds
- keep local startup cost closer to `boot + environment attach` than to `boot + guest package install + guest environment construction`
- make environment resolution and reuse explicit, cached, and host-driven
- preserve Firebreak's runtime boundaries and fail-fast behavior

## Non-goals

- generating a unique full guest OS image for every package or working directory
- allowing arbitrary project Nix to redefine Firebreak's base VM or guest boot graph
- preserving guest-time package installation as the primary environment construction mechanism
- solving every language ecosystem in one changeset

## Direction

Firebreak should adopt a three-layer model:

### 1. Boot base

A small number of Firebreak-owned boot-semantic bases:

- `command`: minimal non-interactive execution base
- `interactive`: minimal interactive shell / attached worker base
- future heavier bases only when a materially different boot contract is required

These bases are about boot semantics, initrd, service graph, and runtime plumbing. They are not package identities.

### 2. Environment overlay

A host-resolved, cached Nix environment layer derived from:

- package-declared Firebreak runtime dependencies
- project-declared local Nix configuration in the working directory
- explicit Firebreak overrides when the user wants them

This layer provides tools, libraries, and project-specific runtime inputs. It shall not redefine the Firebreak base image.

### 3. State layer

Persistent and shared mutable data such as:

- auth and credential slots
- tool state
- caches
- workspace mounts
- task and worker metadata

## Product model

Firebreak shall not model "customization" as "pick a different full OS image per package".

Instead:

- Firebreak owns a small set of base VM classes
- packages declare dependencies and launch behavior
- projects optionally declare additional Nix dependencies
- Firebreak resolves a reusable environment closure on the host
- the guest consumes that closure through shared `/nix/store`, mounted environment paths, and Firebreak-managed env exports

## Environment contract

Firebreak should resolve environments in this precedence order:

1. explicit Firebreak configuration
2. project-local Nix configuration in the active working directory
3. package defaults
4. Firebreak fallback base environment

The environment contract shall be additive and constrained:

- project configuration may add dependencies and environment exports
- package configuration may add dependencies and launch commands
- Firebreak base runtime semantics remain Firebreak-owned

## Cache model

Environment overlays shall be cached by an explicit environment identity that includes at minimum:

- Firebreak runtime version
- selected boot base
- package identity
- relevant project-local Nix lock state and output selection
- environment-level Firebreak options that affect the resulting closure

When the environment identity is unchanged, Firebreak shall reuse the resolved environment without rebuilding it.

## Requirements

- Firebreak shall keep the VM boot base smaller and more stable than the environment layer built on top of it.
- Firebreak shall not require a unique full guest image for every package or workspace.
- Firebreak shall support package-declared Nix dependencies.
- Firebreak shall support project-local Nix dependency declarations for local development workflows.
- Firebreak shall resolve and cache environment overlays on the host rather than constructing them inside the guest on every boot.
- Firebreak shall treat the environment layer as data mounted into or referenced by the guest, not as permission to rewrite the guest base.
- Firebreak shall preserve the shared `/nix/store` model as the default path where the backend supports it.
- Firebreak shall allow cold command and interactive shell paths to select different boot-semantic bases without changing package identity.
- Firebreak shall fail explicitly when a project-local Nix declaration cannot be evaluated or cannot be mapped into the supported Firebreak environment contract.
- Firebreak shall not silently ignore project-local declarations that materially affect the requested environment.

## Proposed implementation shape

### Boot-base work

- continue shrinking kernel, initrd, and service graph for Firebreak-owned base classes
- move local packaged sandboxes onto explicit boot targets for `command` and `interactive`
- keep the number of boot bases intentionally small

### Environment-overlay work

- define a Firebreak environment resolver on the host
- resolve environments from package metadata plus workspace-local Nix declarations
- materialize a reusable environment result keyed by the environment identity
- mount or export the resolved environment into the guest

### Runtime integration

- local launches should request a boot base and an environment identity
- command execution and interactive shells should wait for the environment result when needed
- environment construction should overlap with boot when possible

## Acceptance criteria

- Firebreak can support many packages and many workspaces without defining one guest image per package.
- the repository defines a small explicit set of boot-semantic bases that are independent of package identity.
- package and project dependency customization flows through a host-resolved cached environment layer.
- repeated launches with the same environment identity reuse the resolved environment without reconstructing it.
- Firebreak's base VM remains Firebreak-owned even when the workspace contributes local Nix declarations.

## Dependencies and risks

### Dependencies

- [specs/017-runtime-v2/SPEC.md](../017-runtime-v2/SPEC.md)
- [specs/018-warm-local-command-channel/SPEC.md](../018-warm-local-command-channel/SPEC.md)
- [specs/019-rootless-local-network-facade/SPEC.md](../019-rootless-local-network-facade/SPEC.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)

### Risks

- letting workspace-local Nix drive too much guest shape would blur Firebreak runtime boundaries
- environment identity could be under-specified and allow stale or incorrect reuse
- over-generalizing project-local environment support too early could recreate the complexity of a general-purpose Nix launcher inside Firebreak
- shrinking the base without clear boot-base classes could turn the runtime into a pile of special cases
