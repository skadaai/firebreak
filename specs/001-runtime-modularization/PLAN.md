---
status: draft
last_updated: 2026-03-19
---

# 001 Runtime Modularization Plan

## Implementation slices

1. Identify the current guest-common responsibilities and local-only responsibilities in the base runtime.
2. Introduce a guest-common module boundary that owns shared guest semantics.
3. Introduce a local profile boundary that owns dynamic host cwd, host identity adoption, and interactive console behavior.
4. Recompose the existing local flake outputs through the new module boundaries.
5. Adjust architecture documentation to describe the new shape.

## Validation approach

- confirm the local flake outputs still evaluate
- run the existing local smoke path after the modular split lands
- review the resulting module boundaries against the requirements in the spec

## Dependencies

- existing local smoke coverage in [tool-smoke.sh](./modules/base/tests/tool-smoke.sh)
- the current assembly model in [flake.nix](./flake.nix)

## Current status

Drafted.
Implementation has not started.

## Open questions

- whether the first extraction should create one guest-common module plus one local profile, or a slightly finer split inside the guest layer
- how much of the current file layout should be preserved versus renamed for clarity
