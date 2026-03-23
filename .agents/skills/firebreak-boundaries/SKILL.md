---
name: firebreak-boundaries
description: "Use when a Firebreak task touches files, shared state, or parallel work. This skill enforces write scope, shared-resource boundaries, runtime budgets, and task isolation."
---

# Firebreak Boundaries

Firebreak loop autonomy is allowed only inside explicit limits.

## Checks

1. Declare narrow write paths before acting.
2. Keep shared paths resolved inside the managed task roots.
3. Respect runtime and parallelism budgets.
4. Keep one mutable worktree per active task.

## Rules

- Do not write outside declared scope.
- Do not treat `.codex`, `.claude`, or `.direnv` as safe unless their resolved target stays inside the managed shared root.
- Do not reuse singleton VM state for smoke-style or parallel runs when isolated state is available.
- When a policy limit is hit, stop before the action and record the reason.
