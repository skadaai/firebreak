---
status: draft
last_updated: 2026-04-10
---

# 023 Composable Workload Manifests

## Problem

Firebreak is not meant to stop at the two example workloads currently shipped in-tree.

The real product direction is a broad package ecosystem where developers can define many different Firebreak workloads without needing to fork or understand Firebreak runtime internals.

That creates a scaling problem:

- if each package maps to a bespoke full guest image, the platform will not scale operationally
- if each package can mutate runtime internals freely, the platform will not scale maintainably
- if package authors do not have a clear declarative contract, they will recreate ad hoc wrappers and runtime forks around every tool

Docker solved a similar ecosystem problem by giving image authors a composable build model on top of a shared runtime substrate.

Firebreak needs an equivalent package-authoring model, but it should fit Firebreak's architecture:

- shared runtime substrate
- explicit guest artifacts
- additive environment overlays
- explicit host-runtime adapters
- fail-fast boundaries

## Goals

- define a package-author contract that scales to many third-party Firebreak workloads
- let package authors compose Firebreak-owned runtime primitives rather than reimplementing them
- make workload identity explicit and portable across supported hosts
- preserve a small number of Firebreak-owned boot bases and guest artifact families
- allow broad package customization through additive declarations
- keep package definitions declarative, inspectable, and cache-friendly

## Non-goals

- allowing package authors to redefine Firebreak guest boot semantics arbitrarily
- allowing package authors to ship ad hoc host-runtime implementations as part of the public package contract
- replacing the environment overlay model from [spec 020](../020-minimal-boot-bases-and-environment-overlays/SPEC.md)
- replacing the artifact-first runtime model from [spec 022](../022-artifact-first-multi-host-runtime/SPEC.md)
- designing a general-purpose OCI-compatible image format in this changeset
- defining every future package recipe helper in advance

## Direction

Firebreak should adopt a composable workload-manifest model.

A Firebreak package should not mean "a custom VM image".

A Firebreak package should mean "a workload manifest that composes Firebreak runtime components".

That manifest should point at a small number of Firebreak-owned primitives plus package-owned additive declarations.

## Product model

Firebreak should expose two layers of ownership.

### Firebreak-owned platform primitives

Firebreak owns:

- boot bases
- guest artifact families
- host-runtime adapters
- runtime capability contracts
- state-root and credential-slot semantics
- environment-overlay resolution rules

These are platform concerns and must remain coherent across the ecosystem.

### Package-owned workload declarations

Package authors own:

- workload name and human-facing metadata
- default command and entry mode
- environment-overlay inputs
- required runtime capabilities
- optional seed artifacts and helper tools
- package-specific validation declarations

These are workload concerns and should be composable without redefining the platform.

## Workload manifest model

A Firebreak workload manifest should resolve from the following conceptual fields.

### 1. Runtime class selection

The manifest selects the Firebreak runtime class it needs, not a bespoke runtime implementation.

Examples:

- local interactive workload
- local command workload
- future remote/cloud job workload

This selection expresses the runtime contract, not the package identity.

### 2. Boot-base selection

The manifest selects from Firebreak-owned boot bases.

Examples:

- `command`
- `interactive`

The package may express which boot base is appropriate for a given execution mode, but it shall not define new boot semantics by itself without an explicit Firebreak-level spec.

### 3. Guest artifact selection

The manifest references a guest artifact family compatible with the selected runtime class and guest architecture.

The package should resolve through Firebreak's canonical guest artifact naming rather than producing a package-private guest image by default.

### 4. Environment overlay declaration

The manifest declares additive overlay inputs such as:

- package installables
- package path exports
- package environment variables
- optional project-local overlay participation

This is where most package differentiation should live.

### 5. State and credential policy

The manifest may declare how it participates in Firebreak state primitives:

- state-root defaults
- credential-slot bindings
- shared-state requirements

It should use Firebreak's shared state model rather than inventing package-private persistence contracts.

### 6. Capability requirements

The manifest declares required capabilities such as:

- interactive console
- rootless local hypervisor
- guest egress
- host port publishing
- worker bridge support

Packages declare capabilities they need.
Firebreak owns how those capabilities are satisfied.

### 7. Validation surface

The manifest should declare or point at its validation contract:

- smoke packages
- representative coverage class
- host-system support

That makes ecosystem growth easier to reason about in CI and diagnostics.

## Composition rules

The composable workload-manifest model should follow strict rules.

### Allowed package composition

Packages may:

- select a Firebreak runtime class
- select among Firebreak-owned boot bases
- request a compatible guest artifact family
- declare additive environment overlays
- declare runtime capabilities
- declare validation metadata
- declare package-specific helper tools and seed artifacts

### Disallowed package composition

Packages shall not:

- redefine Firebreak guest boot semantics ad hoc
- bypass Firebreak capability gating with package-private backend logic
- redefine shared state-root and credential-slot semantics incompatibly
- ship package-private copies of generic host-runtime wrappers as the public contract
- make package identity equal guest-image identity by default

## Why this scales

This model is intended to support thousands of packages because package growth happens in manifests and overlays rather than in duplicated guest systems.

That means:

- many packages can share the same boot base
- many packages can share the same guest artifact family
- many packages can differ only by environment overlay and command contract
- hosts can resolve the same package manifest differently only where host-runtime concerns actually differ

The scaling unit should be:

- workload manifests

not:

- bespoke VM images

## Package author experience

The intended package-author workflow should look like this:

1. choose a Firebreak runtime class
2. choose the appropriate Firebreak boot base
3. declare package-specific overlay inputs
4. declare required capabilities
5. declare validation metadata
6. publish the workload manifest

The author should not need to:

- reason about guest boot plumbing
- reason about hypervisor command lines
- fork Firebreak wrapper logic
- assemble a full guest image for routine package differences

## Identity and publication model

The manifest model should make identity explicit.

### Workload identity

A workload identity should include at minimum:

- package name
- manifest version
- selected runtime class
- selected boot-base mapping
- environment overlay identity inputs
- capability requirements

### Artifact identity

The workload manifest should point to Firebreak-owned guest artifact identities and host-runtime compatibility, not hide those under opaque package-private derivations.

### Publication

Publishing a package should mean publishing:

- the workload manifest
- additive overlay inputs
- any package-owned seed artifacts

It should not imply publication of a distinct full guest OS image unless a future explicit spec says so.

## Requirements

- Firebreak shall define a package-author contract in terms of composable workload manifests.
- Firebreak shall keep runtime substrate ownership separate from package-owned workload declarations.
- Firebreak shall allow packages to select Firebreak-owned runtime classes and boot bases without redefining them.
- Firebreak shall keep package-specific customization primarily in additive environment overlays and capability declarations.
- Firebreak shall let many packages reuse the same guest artifact families where guest semantics are equivalent.
- Firebreak shall preserve explicit capability declarations as the package-level way to request runtime behavior.
- Firebreak shall make workload-manifest identity inspectable enough for diagnostics, CI selection, and cache reasoning.
- Firebreak shall not require package authors to define bespoke guest images for ordinary workload differentiation.
- Firebreak shall fail explicitly when a package requests capabilities or runtime combinations that Firebreak cannot satisfy.
- Firebreak shall preserve room for specialized packages later, but those exceptions shall require an explicit Firebreak-level contract instead of silently expanding the package surface.

## Proposed implementation shape

### 1. Define the manifest schema

- define the fields Firebreak packages may declare
- define which fields are package-owned versus Firebreak-owned
- keep the schema intentionally narrow at first

### 2. Align recipe helpers with the schema

- make package helper functions emit workload-manifest-aligned declarations
- reduce ad hoc wrapper behavior hidden inside individual package helpers

### 3. Expose identity in diagnostics

- make `firebreak doctor` and related tooling show the resolved workload identity
- distinguish runtime class, guest artifact, overlay identity, and state selectors

### 4. Use manifest metadata in CI

- let CI selection reason about workload capabilities and support matrices through manifest-aligned metadata
- keep package growth manageable without hand-maintained workflow lists

### 5. Keep exceptions explicit

- if a package truly needs a specialized guest artifact or runtime path, require a dedicated explicit contract
- do not let "just one package" create a silent new packaging model

## Acceptance criteria

- Firebreak package definitions can scale beyond the in-tree example workloads without multiplying bespoke full guest images.
- Package authors can define a workload in terms of runtime class, boot base, overlays, and capabilities without forking Firebreak runtime internals.
- Multiple workloads can reuse the same Firebreak-owned guest artifact family while differing only in overlays, launch command, and capability declarations.
- Diagnostics and CI can inspect workload-manifest identity rather than reverse-engineering package behavior from ad hoc wrappers.
- The repository has a clear basis for future ecosystem package helpers that does not special-case `codex` and `claude` as the permanent model.

## Dependencies and risks

### Dependencies

- [spec 001](../001-runtime-modularization/SPEC.md)
- [spec 009](../009-project-config-and-doctor/SPEC.md)
- [spec 016](../016-state-roots-and-credential-slots/SPEC.md)
- [spec 020](../020-minimal-boot-bases-and-environment-overlays/SPEC.md)
- [spec 022](../022-artifact-first-multi-host-runtime/SPEC.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)

### Risks

- if the manifest schema is too loose, package authors will smuggle runtime internals back through package declarations
- if the manifest schema is too narrow, package authors will keep building ad hoc wrapper layers outside the intended contract
- if Firebreak does not distinguish package identity from guest artifact identity clearly enough, ecosystem growth will recreate per-package VM image sprawl
- if package helpers encode special treatment for in-tree example workloads, the ecosystem contract will drift from the product contract
