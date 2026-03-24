---
name: firebreak-work-task
description: "Use when a Firebreak task will edit code, validate a slice, or review autonomous work. This skill keeps work inside an isolated Firebreak task and out of the primary checkout."
---

# Firebreak Work Task

Use one task per bounded attempt.

## Workflow

1. Create or resume a task before substantial work.
2. Work only inside the task worktree.
3. Use task-owned VM state, validation artifacts, and review artifacts.
4. Close the task with a real disposition when the attempt ends.

## Rules

- Never edit the primary checkout for autonomous work.
- Never invent duplicate task IDs. Resume or stop instead.
- Treat the task as the unit of change, validation, review, and cleanup.
- Treat `.codex`, `.claude`, and `.direnv` as shared across sibling worktrees unless the task owns the resolved path.
