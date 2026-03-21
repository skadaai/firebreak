---
name: firebreak-work-session
description: "Use when a Firebreak task will edit code, validate a slice, or review autonomous work. This skill keeps work inside an isolated Firebreak session and out of the primary checkout."
---

# Firebreak Work Session

Use one session per bounded attempt.

## Workflow

1. Create or resume a session before substantial work.
2. Work only inside the session worktree.
3. Use session-owned VM state, validation artifacts, and review artifacts.
4. Close the session with a real disposition when the attempt ends.

## Rules

- Never edit the primary checkout for autonomous work.
- Never invent duplicate session IDs. Resume or stop instead.
- Treat the session as the unit of change, validation, review, and cleanup.
- Treat `.codex`, `.claude`, and `.direnv` as shared across sibling worktrees unless the session owns the resolved path.
