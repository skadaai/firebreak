---
status: draft
last_updated: 2026-03-20
---

# 005 Isolated Work Sessions Status

## Current phase

Draft.

## What has landed

- the isolated work-session changeset has been scoped
- behavioral acceptance has been defined at the spec level

## What remains open

- implementation of the session layout and metadata model
- integration of isolated VM-state roots across execution paths
- lifecycle handling for duplicate, resumed, and cleaned-up sessions

## Current sources of truth

- [spec](./SPEC.md)
- [plan](./PLAN.md)
- [acceptance](./acceptance/001-work-session-lifecycle.feature)

## History

- 2026-03-20: Spec created to define parallel-safe work sessions for autonomous Firebreak agents and sub-agents.
