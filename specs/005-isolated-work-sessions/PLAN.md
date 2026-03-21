---
status: completed
last_updated: 2026-03-21
---

# 005 Isolated Work Sessions Plan

## Implementation slices

1. Define the work-session directory layout and metadata contract.
2. Extend or replace the current worktree helper so sessions can create and resume isolated checkouts.
3. Thread isolated VM-state roots through local and remote Firebreak execution paths.
4. Persist session artifacts and validation outputs under the session root.
5. Add deterministic cleanup and resume-or-reject behavior.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- verify session creation from the primary checkout
- verify concurrent sessions do not collide on VM state or worktree mutation
- verify duplicate session requests are deterministic

## Dependencies

- [scripts/new-worktree.sh](../../scripts/new-worktree.sh)
- the local and cloud VM wrappers under [modules/profiles/](../../modules/profiles)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)

## Current status

Implemented.
The Firebreak session harness, session smoke coverage, and isolated VM-state wiring are in place.

## Open questions

- whether a later revision should add explicit parent-child sub-agent relationships
- whether cleanup retention windows should become configurable beyond explicit close/disposition handling
