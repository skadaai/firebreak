---
status: completed
last_updated: 2026-04-02
---

# 005 Isolated Workspaces Plan

## Implementation slices

1. Define the workspace directory layout and metadata contract.
2. Extend or replace the current worktree helper so workspaces can create and resume isolated checkouts.
3. Thread isolated VM-state roots through local and remote Firebreak execution paths.
4. Persist workspace artifacts and validation outputs under the workspace state root.
5. Add deterministic cleanup and resume-or-reject behavior.
6. Distinguish attempt lifecycle from workspace lifecycle so one spec line can reuse one workspace across sequential slices.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- verify workspace creation from the primary checkout
- verify concurrent workspaces do not collide on VM state or worktree mutation
- verify duplicate workspace requests are deterministic
- verify sequential work on the same spec can reuse the same workspace

## Dependencies

- [scripts/new-worktree.sh](../../scripts/new-worktree.sh)
- the local and cloud VM wrappers under [modules/profiles/](../../modules/profiles)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)

## Current status

Implemented.
The dev-flow workspace harness, workspace smoke coverage, and isolated VM-state wiring are in place.

## Open questions

- whether a later revision should add explicit parent-child sub-agent relationships
- whether cleanup retention windows should become configurable beyond explicit close/disposition handling
