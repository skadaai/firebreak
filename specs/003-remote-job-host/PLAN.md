---
status: draft
last_updated: 2026-03-19
---

# 003 Remote Job Host Plan

## Implementation slices

1. Define the host-side job directory contract for workspace, outputs, config, and transient runtime state.
2. Implement a bounded single-host runner that launches the existing Firebreak VM boundary against those prepared paths.
3. Add host-side timeout and capacity guardrails.
4. Add behavioral validation for success, rejection, and timeout paths.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- exercise at least one successful remote job run end to end
- verify pre-launch rejection on invalid inputs and exhausted capacity
- verify timeout handling returns a diagnosable result

## Dependencies

- [spec 001](./specs/001-runtime-modularization/SPEC.md)
- [spec 002](./specs/002-cloud-execution-profile/SPEC.md)

## Current status

Drafted.
Implementation has not started.

## Open questions

- whether the first host runner should be exposed as a shell wrapper, a systemd unit interface, or both
- how much per-agent configuration persistence the first host runner should support
