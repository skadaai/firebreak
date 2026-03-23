---
name: firebreak-work-task
description: "Use when a Firebreak task will edit code, validate a slice, or review autonomous work. This skill keeps the task bounded and chooses the simplest safe workspace for it."
---

# Firebreak Work Task

Use one task per bounded attempt. Do not assume that means a fresh branch or worktree.

## Workflow

1. Start from the current safe workspace when one already exists for the slice.
2. Create or resume an isolated task worktree only when parallel, risky, or branch-sensitive work needs it.
3. Keep validation, review, and cleanup tied to the task regardless of workspace choice.
4. Close the task with a real disposition when the attempt ends.

## Rules

- Prefer reusing the current safe workspace for sequential work.
- Create a fresh worktree only when it buys real safety or review clarity.
- Never invent duplicate task IDs. Resume or stop instead.
- Treat the task as the unit of change, validation, review, and cleanup.
- Treat `.codex`, `.claude`, and `.direnv` as shared across sibling worktrees unless the task owns the resolved path.
