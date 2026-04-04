---
status: in_progress
last_updated: 2026-03-24
---

# 013 Status

## Current phase

Implemented in the workspace checkout and validated through flake evaluation plus launcher smoke coverage. Real Apple Silicon runtime validation remains open.

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
- host/guest flake wiring for `aarch64-darwin` local packages with `aarch64-linux` guests
- Apple Silicon launcher, doctor, and validation capability handling
- internal Apple Silicon `vfkit` local runtime path
- Linux-only cloud package boundary

## What remains open

- real local boot validation on Apple Silicon hardware
- confirmation that launch-time `vfkit` share injection behaves correctly under interactive local use

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec after deciding that Apple Silicon local support is the next meaningful platform feature, while generalized runner choice and cloud macOS support remain out of scope.
- 2026-03-24: Landed the first implementation slice in the workspace checkout with evaluation-oriented validation and launcher smoke coverage.
