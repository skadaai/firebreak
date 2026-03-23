---
name: firebreak-boundaries
description: "Use when a Firebreak task touches files, shared state, or parallel work. This skill enforces write scope, shared-resource boundaries, runtime budgets, and the simplest safe workspace choice."
---

# Firebreak Boundaries

Firebreak loop autonomy is allowed only inside explicit limits.

## Checks

1. Declare narrow write paths before acting.
2. Keep shared paths resolved inside the managed roots for the chosen workspace.
3. Respect runtime and parallelism budgets.
4. Escalate to an isolated worktree only when the current workspace is not safe enough.

## Rules

- Do not write outside declared scope.
- Do not treat `.codex`, `.claude`, or `.direnv` as safe unless their resolved target stays inside the managed shared root.
- Do not create a fresh worktree for routine sequential slices without a concrete isolation reason.
- Do not reuse singleton VM state for smoke-style or parallel runs when isolated state is available.
- When a policy limit is hit, stop before the action and record the reason.
