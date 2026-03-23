---
status: in_progress
last_updated: 2026-03-23
---

# 007 Status

## Current phase

Drafted for implementation.

## What has landed

- the desired command moves and naming direction have been agreed:
  - `firebreak session ...` -> `firebreak internal task ...`
  - `firebreak validate ...` -> `firebreak internal validate run ...`
  - `firebreak autonomy run ...` -> `firebreak internal loop run ...`
- smoke naming should be test-prefixed instead of suffix-based

## What remains open

- renaming package outputs
- renaming suite names
- renaming checks and workflow references
- updating docs and host-side scripts

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to govern the human/internal CLI split, the `task` rename, and the package/test naming migration.
