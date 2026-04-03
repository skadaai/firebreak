---
name: firebreak-work-task
description: "Use when autonomous work will edit code, validate a slice, or review a change. This skill keeps work inside an isolated workspace and out of the primary checkout."
---

# Firebreak Work Task

Use one workspace per spec line.

## Order

Use this skill after `firebreak-spec-driving` identifies the owning spec or maintenance line, and before substantial edits, validation, or review.

## Workflow

1. Identify the spec or other logical work line that owns the change.
2. If the current workspace already belongs to that spec, reuse it for sequential work.
3. If the work moves to a different spec or unrelated maintenance line, create or resume a separate workspace before substantial edits.
4. Use `dev-flow workspace ...` or the repo helper scripts to create, inspect, or close the workspace.
5. Do code changes, validation, and review only inside that workspace checkout.
6. Use workspace-owned VM state, validation artifacts, and review artifacts.
7. Close the workspace with a real disposition when that line of work is done or parked.

## Rules

- Never edit the primary checkout for autonomous work.
- Never invent duplicate workspace IDs. Resume or stop instead.
- Reuse the current workspace for the same spec; start a new workspace when the spec changes.
- Treat `.codex`, `.claude`, and `.direnv` as shared across sibling workspaces unless the workspace owns the resolved path.

## Example

- Continue using the current workspace while implementing multiple sequential slices of the same spec.
- Start a different workspace before editing when the next request belongs to another spec, another branch of work, or unrelated cleanup.
