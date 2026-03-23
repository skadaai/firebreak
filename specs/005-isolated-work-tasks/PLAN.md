---
status: completed
last_updated: 2026-03-21
---

# 005 Isolated Work Tasks Plan

## Implementation slices

1. Define the work-task directory layout and metadata contract.
2. Extend or replace the current worktree helper so tasks can create and resume isolated checkouts.
3. Thread isolated VM-state roots through local and remote Firebreak execution paths.
4. Persist task artifacts and validation outputs under the task root.
5. Add deterministic cleanup and resume-or-reject behavior.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- verify task creation from the primary checkout
- verify concurrent tasks do not collide on VM state or worktree mutation
- verify duplicate task requests are deterministic

## Dependencies

- [scripts/new-worktree.sh](../../scripts/new-worktree.sh)
- the local and cloud VM wrappers under [modules/profiles/](../../modules/profiles)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)

## Current status

Implemented.
The Firebreak task harness, internal task smoke coverage, and isolated VM-state wiring are in place.

## Open questions

- whether a later revision should add explicit parent-child sub-agent relationships
- whether cleanup retention windows should become configurable beyond explicit close/disposition handling
