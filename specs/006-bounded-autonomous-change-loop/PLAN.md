---
status: completed
last_updated: 2026-03-21
---

# 006 Bounded Autonomous Change Loop Plan

## Implementation slices

1. Define the autonomous attempt record and audit-log contract.
2. Define how tracked specs, work tasks, and validation suites are selected for a change attempt.
3. Implement the bounded execution stages: plan, implement, validate, review, and disposition.
4. Add stop conditions for missing capability, validation failure, and policy violations.
5. Wire commit creation and final summaries to the audit record.

## Validation approach

- add behavioral acceptance scenarios under `acceptance/`
- exercise a successful autonomous change attempt in a bounded task
- exercise blocked paths for missing validation capability and policy violations
- review whether the resulting audit trail is sufficient for a maintainer to reconstruct what happened

## Dependencies

- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [spec 005](../005-isolated-work-tasks/SPEC.md)
- the current repo conventions in [engineering/SPECS.md](../../engineering/SPECS.md) and [AGENTS.md](../../AGENTS.md)

## Current status

Implemented.
The first bounded autonomous loop now records plan state, enforces pre-action policy, runs required validation suites, performs a review pass, and creates an auditable commit when requested.

## Open questions

- whether later revisions should capture richer semantic review findings beyond diff hygiene and validation coverage
- whether multi-slice attempt histories should roll up into a higher-level operator timeline
