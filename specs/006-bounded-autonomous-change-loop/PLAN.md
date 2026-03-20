---
status: draft
last_updated: 2026-03-20
---

# 006 Bounded Autonomous Change Loop Plan

## Implementation slices

1. Define the autonomous attempt record and audit-log contract.
2. Define how tracked specs, work sessions, and validation suites are selected for a change attempt.
3. Implement the bounded execution stages: plan, implement, validate, review, and disposition.
4. Add stop conditions for missing capability, validation failure, and policy violations.
5. Wire commit creation and final summaries to the audit record.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- exercise a successful autonomous change attempt in a bounded session
- exercise blocked paths for missing validation capability and policy violations
- review whether the resulting audit trail is sufficient for a maintainer to reconstruct what happened

## Dependencies

- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [spec 005](../005-isolated-work-sessions/SPEC.md)
- the current repo conventions in [engineering/SPECS.md](../../engineering/SPECS.md) and [AGENTS.md](../../AGENTS.md)

## Current status

Drafted.
Implementation has not started.

## Open questions

- whether the first audit record should be plain files, JSON, or both
- how much retry policy should be centralized versus task-specific
- whether commit creation should be built into the first loop or land in a second slice after plan/validate/review are stable
