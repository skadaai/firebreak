---
status: draft
last_updated: 2026-03-19
---

# 002 Cloud Execution Profile Plan

## Implementation slices

1. Define the guest-facing cloud profile contract and the local-only behaviors it disables.
2. Wire the cloud profile through the modularized guest runtime.
3. Reuse or adapt the current one-shot execution path so it becomes a first-class cloud workflow.
4. Add cloud-focused validation coverage for success and failure cases.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- add or adapt smoke coverage so the cloud profile can be exercised non-interactively
- verify fixed workspace, fixed config, persisted outputs, and shutdown behavior

## Dependencies

- [spec 001](./specs/001-runtime-modularization/SPEC.md)
- existing one-shot execution semantics in [dev-console-start.sh](./modules/base/guest/dev-console-start.sh)

## Current status

Drafted.
Implementation has not started.

## Open questions

- whether cloud mode should always require an explicit command or allow a profile default
- whether cloud mode should support a maintenance shell behind a non-default debug path
