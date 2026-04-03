---
name: firebreak-work-task
description: "Use when autonomous work will edit code, validate a slice, or review a change. This skill keeps work inside an isolated workspace and out of the primary checkout."
---

# Firebreak Work Task

Use one workspace per spec line.

## Workflow

1. Identify the spec or other logical work line that owns the change.
2. If the active workspace already belongs to that spec, reuse it for sequential work.
3. If the work moves to a different spec or unrelated maintenance line, create or resume a separate workspace before substantial edits.
4. Do code changes, validation, and review only inside that workspace.
5. Close the workspace with a real disposition when that line of work is done or parked.

## Rules

- Never edit the primary checkout for autonomous work.
- Never invent duplicate workspace IDs. Resume or stop instead.
- Reuse the current workspace for the same spec; start a new workspace when the spec changes.
- Treat `.codex`, `.claude`, and `.direnv` as shared across sibling workspaces unless the workspace owns the resolved path.
