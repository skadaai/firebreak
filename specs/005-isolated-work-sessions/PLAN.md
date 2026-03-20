---
status: draft
last_updated: 2026-03-20
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

Drafted.
Implementation has not started.

## Open questions

- whether the first session contract should support explicit parent-child sub-agent relationships
- how much cleanup policy should be configurable in the first version
- whether session metadata should be plain files, JSON, or both
