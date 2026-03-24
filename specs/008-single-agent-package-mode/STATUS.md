---
status: completed
last_updated: 2026-03-23
---

# 008 Status

## Current phase

Implemented.

## What has landed

- public local packages now ship one package per workload instead of separate `*-shell` siblings
- the local wrapper defaults to `run` mode semantics and now documents `FIREBREAK_VM_MODE=shell` as the public shell override
- the local smoke harness validates shell behavior through the same public package
- legacy public mode aliases were removed from the local wrapper implementation
- docs and architecture guidance now describe the single-package local-launch model

## What remains open

- none in this changeset

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to collapse public local packages into one package per workload while preserving a semantic shell override.
- 2026-03-23: Implemented the package collapse, migrated smoke coverage to the shell override path, and updated docs.
- 2026-03-23: Reopened the changeset so the public contract converges on `FIREBREAK_VM_MODE` without legacy mode aliases.
- 2026-03-23: Removed the legacy public mode aliases from the implementation and completed the changeset.
