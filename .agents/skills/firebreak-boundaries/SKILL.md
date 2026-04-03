---
name: firebreak-boundaries
description: "Use when an autonomous workspace touches files, shared directories, or parallel execution. This skill requires explicit write scope, safe shared-path handling, runtime budgets, and workspace isolation."
---

# Firebreak Boundaries

Firebreak autonomy applies only inside explicit boundaries. Before acting, define what the workspace may change and verify that any shared or mutable state stays inside approved roots.

## Checks

1. Declare the exact files or directories the workspace may modify before making changes.
2. For shared paths or symlinks, verify that the resolved destination stays inside the workspace's managed root or approved shared root.
3. Stay within the workspace's runtime and parallelism budgets.
4. Give each active workspace its own writable checkout and isolated mutable state when available.

## Rules

- Do not write outside declared scope.
- Treat `.codex`, `.claude`, `.direnv`, and similar directories as unsafe by default. Only use them if their resolved target stays inside the approved shared root for the workspace.
- Do not reuse singleton VM or runtime state for smoke tests or parallel runs when isolated state is available.
- If a scope, isolation, or budget limit would be exceeded, stop before the action and record the reason.
