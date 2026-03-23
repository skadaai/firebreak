---
status: completed
last_updated: 2026-03-23
---

# 011 Plan

## Implementation slices

1. Define the decomposition contract in this spec.
2. Extract shared flake helper builders into a support file under `nix/`.
3. Extract `nixosModules`, `nixosConfigurations`, `packages`, and `checks` into focused output files under `nix/outputs/`.
4. Reduce `flake.nix` to shared context plus final output assembly.
5. Update architecture and repository guidance to describe the new flake layout.

## Validation approach

- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex-version`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- current package and check wiring in [flake.nix](../../flake.nix)
- repository structure guidance in [ARCHITECTURE.md](../../ARCHITECTURE.md) and [AGENTS.md](../../AGENTS.md)

## Current status

Implemented and validated.

## Open questions

- none; the single-flake direction is already chosen for this changeset
