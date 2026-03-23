---
status: completed
last_updated: 2026-03-23
---

# 008 Status

## Current phase

Implemented and validated.

## What has landed

- public local packages now ship one package per workload instead of separate `*-shell` siblings
- the local wrapper defaults to `run` mode semantics and now documents `FIREBREAK_VM_MODE=shell` as the public shell override
- the local wrapper still accepts `FIREBREAK_AGENT_MODE` and `AGENT_VM_ENTRYPOINT` as compatibility aliases
- the local smoke harness validates shell behavior through the same public package
- docs and architecture guidance now describe the single-package local-launch model

## What remains open

- a future human-facing CLI flag for shell mode remains explicitly deferred

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to collapse public local packages into one package per workload while preserving a semantic shell override.
- 2026-03-23: Implemented the package collapse, migrated smoke coverage to the shell override path, and updated docs.
