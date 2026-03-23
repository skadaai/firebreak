---
status: completed
last_updated: 2026-03-23
---

# 008 Status

## Current phase

Implemented and validated.

## What has landed

- public local agent packages now ship one package per agent instead of separate `*-shell` siblings
- the local wrapper defaults to `agent` mode and still accepts `AGENT_VM_ENTRYPOINT=shell`
- the local smoke harness validates shell behavior through the same public package
- docs and architecture guidance now describe the single-package local-launch model

## What remains open

- a future human-facing CLI flag for shell mode remains explicitly deferred

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to collapse public local agent packages into one package per agent while preserving a semantic shell override.
- 2026-03-23: Implemented the package collapse, migrated smoke coverage to the shell override path, and updated docs.
