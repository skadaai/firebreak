---
status: in_progress
last_updated: 2026-04-02
---

# 007 Status

## Current phase

Implementation in progress.

## What has landed

- the top-level `firebreak` CLI is being narrowed to the human-facing surface
- the separate `dev-flow` CLI now owns workspace, validation, and loop commands
- the host-side isolated checkout concept is named `workspace` and the bounded loop unit is named `attempt`
- workflow packages now use `dev-flow-*` names
- docs, workflows, and agent guidance are being updated to the new command and naming contract

## What remains open

- cleanup of remaining historical references to `task` and `firebreak internal ...`
- optional renaming of internal-only runner package identifiers such as `firebreak-internal-runner-*`

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to govern the human/internal CLI split, the `task` rename, and the package/test naming migration.
- 2026-04-02: Revised the spec to separate attempts from workspaces and to move agent workflow commands into the separate `dev-flow` CLI.
