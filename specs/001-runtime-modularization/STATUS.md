---
status: draft
last_updated: 2026-03-19
---

# 001 Runtime Modularization Status

## Current phase

Draft.

## What has landed

- the changeset has been defined and scoped

## What remains open

- implementation of the module split
- validation that local behavior is preserved
- documentation updates that reflect the final module boundaries

## Current sources of truth

- [spec](./specs/001-runtime-modularization/SPEC.md)
- [plan](./specs/001-runtime-modularization/PLAN.md)
- [flake.nix](./flake.nix)
- [module.nix](./modules/base/module.nix)

## History

- 2026-03-19: Spec created to define the architectural split between reusable guest runtime behavior and local-launch behavior before cloud work begins.
