---
status: completed
last_updated: 2026-03-23
---

# 011 Flake Decomposition

## Problem

`flake.nix` currently owns both the public flake contract and most of the flake's implementation details.

That file now contains:

- shared builder helpers
- NixOS module wiring
- NixOS configuration wiring
- package wiring
- check wiring

The result is a dense assembly file that is harder to review, extend, and navigate than the rest of the repository's module-oriented structure.

## Affected users, actors, or systems

- maintainers editing Firebreak flake outputs
- coding agents navigating and modifying the flake
- reviewers trying to distinguish public contract changes from internal assembly refactors

## Goals

- keep one canonical `flake.nix`
- move flake implementation details into imported support and output files
- make `flake.nix` read like assembly glue instead of an implementation bucket
- preserve the existing public and internal flake surfaces

## Non-goals

- creating a second dev-only flake entrypoint
- changing package names, check names, or NixOS configuration names
- redesigning Firebreak's product surface

## Morphology and scope of the changeset

This changeset is structural and operational.

It keeps one canonical flake interface and decomposes the implementation behind it into focused files under `nix/`.

The intended landing shape is:

- `flake.nix` defines inputs, shared context, and final assembled outputs
- helper constructors live outside `flake.nix`
- `nixosModules`, `nixosConfigurations`, `packages`, and `checks` are each assembled from focused imported files

## Requirements

- The system shall keep a single canonical `flake.nix` entrypoint for Firebreak.
- The system shall move flake implementation helpers out of `flake.nix` into imported support files.
- The system shall assemble `nixosModules`, `nixosConfigurations`, `packages`, and `checks` from focused imported files.
- The system shall preserve the existing flake output names and behavior for this changeset.
- The system shall keep `flake.nix` as assembly glue rather than the primary home of runtime construction logic.

## Acceptance criteria

- `flake.nix` is materially smaller and primarily assembles imported attrsets and helpers.
- helper constructors are defined outside `flake.nix`.
- `nixosModules`, `nixosConfigurations`, `packages`, and `checks` are each sourced from focused files under `nix/`.
- existing flake commands continue to evaluate and validate successfully.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- current [flake.nix](../../flake.nix)

### Risks

- partial decomposition could make the flake harder to follow than before
- careless import boundaries could introduce recursion or broken output references
- documentation could drift if it continues to describe all flake logic as living in `flake.nix`

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
