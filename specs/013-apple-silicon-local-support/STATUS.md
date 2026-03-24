---
status: draft
last_updated: 2026-03-24
---

# 013 Status

## Current phase

Specification drafted. No implementation work has landed.

## What has landed

- a tracked spec, plan, and status record for Apple Silicon local Firebreak support
- a narrow product decision for this changeset:
  - Apple Silicon only
  - local only
  - `vfkit` only
  - `aarch64-linux` guests only
  - no Intel Mac support
  - no cloud macOS support
  - no generic runtime-profile selection

## What remains open

- all implementation work
- the exact local-share contract for the Apple Silicon path
- real Apple Silicon validation

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec after deciding that Apple Silicon local support is the next meaningful platform feature, while generalized runner choice and cloud macOS support remain out of scope.
