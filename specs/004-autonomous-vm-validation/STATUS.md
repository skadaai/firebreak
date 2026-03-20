---
status: draft
last_updated: 2026-03-20
---

# 004 Autonomous VM Validation Status

## Current phase

Draft.

## What has landed

- the autonomous VM validation changeset has been scoped
- behavioral acceptance has been defined at the spec level

## What remains open

- implementation of the host-side validation entrypoint
- capability detection for blocked versus runnable hosts
- machine-readable summaries and artifact retention

## Current sources of truth

- [spec](./SPEC.md)
- [plan](./PLAN.md)
- [acceptance](./acceptance/001-autonomous-vm-validation.feature)

## History

- 2026-03-20: Spec created to define a self-service VM validation harness that autonomous Firebreak operators can invoke without human intervention.
