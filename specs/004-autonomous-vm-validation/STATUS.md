---
status: completed
last_updated: 2026-03-20
---

# 004 Autonomous VM Validation Status

## Current phase

Completed.

## What has landed

- a host-side `dev-flow validate run` entrypoint for named VM validation suites
- capability detection that reports blocked hosts without turning them into false regressions
- machine-readable summaries with persisted stdout, stderr, and exit-code artifacts
- a dedicated validation smoke that exercises both runnable and blocked validation flows
- worktree-safe flake execution for validation and smoke commands

## What remains open

- retention policy tuning for long-lived autonomous hosts
- any future expansion of suite metadata beyond the first KVM-oriented capability contract

## Current sources of truth

- [spec](./SPEC.md)
- [plan](./PLAN.md)
- [acceptance](./acceptance/001-autonomous-vm-validation.feature)

## History

- 2026-03-20: Spec created to define a self-service VM validation harness that autonomous Firebreak operators can invoke without human intervention.
- 2026-03-20: Implemented the validation harness, persisted validation artifacts, and added validation smoke coverage for runnable and blocked hosts.
