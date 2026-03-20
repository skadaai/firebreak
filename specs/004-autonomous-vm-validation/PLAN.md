---
status: completed
last_updated: 2026-03-20
---

# 004 Autonomous VM Validation Plan

## Implementation slices

1. Define the validation-suite registry and the machine-readable result contract.
2. Add host capability detection for required VM features such as KVM availability.
3. Wrap existing Firebreak smoke and cloud validation commands behind the new validation entrypoint.
4. Persist suite artifacts and summaries under stable host paths.
5. Repoint autonomous callers and docs to the new entrypoint.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- exercise both a runnable KVM-backed host and a deliberately blocked host path
- confirm artifact and summary output for both success and blocked outcomes
- review whether the harness can be called non-interactively by later autonomous loops

## Dependencies

- existing smoke packages in [flake.nix](../../flake.nix)
- KVM-aware GitHub Actions behavior in [vm-smoke workflow](../../.github/workflows/vm-smoke.yml)
- the upstream runner/host boundary described by `microvm.nix`

## Current status

Completed.
The validation harness, top-level CLI entrypoint, and validation smoke are implemented and validated on both runnable and deliberately blocked paths.

## Open questions

- how much artifact retention policy the first version should expose versus hardcode
- whether blocked-host detection should later expand beyond local capability checks
