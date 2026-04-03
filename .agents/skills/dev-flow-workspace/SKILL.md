---
name: dev-flow-workspace
description: "Use when autonomous work will edit code, validate a slice, or review a change. This skill keeps work inside an isolated workspace and out of the primary checkout."
---

# Dev Flow Workspace

Use one workspace per spec line.

## Inputs

- one owning spec or maintenance line
- the current workspace context, if one exists
- naming information for the desired workspace and branch

## Outputs

- `workspace_id`
- `branch`
- `reuse_or_create`
- `shared_path_constraints`

## Order

Use this skill after `dev-flow-spec-driving` identifies the owning spec or maintenance line, and before substantial edits, validation, or review.

## Workflow

1. Identify the spec or other logical work line that owns the change.
2. If the current workspace already belongs to that spec, reuse it for sequential work.
3. If the work moves to a different spec or unrelated maintenance line, create or resume a separate workspace before substantial edits.
4. Name the workspace and branch consistently. See [../dev-flow-autonomous-flow/references/naming.md](../dev-flow-autonomous-flow/references/naming.md).
5. Use `dev-flow workspace ...` or the repo helper scripts to create, inspect, or close the workspace.
6. Do code changes, validation, and review only inside that workspace checkout.
7. Use workspace-owned VM state, validation artifacts, and review artifacts.
8. Close the workspace with a real disposition when that line of work is done or parked.

## Rules

- Never edit the primary checkout for autonomous work.
- Never invent duplicate workspace IDs. Resume or stop instead.
- Reuse the current workspace for the same spec; start a new workspace when the spec changes.
- Treat `.codex`, `.claude`, and `.direnv` as shared across sibling workspaces unless the workspace owns the resolved path.

## Anti-Patterns

- Do not create a new workspace for every slice of the same spec.
- Do not create a new workspace just because the next change touches a different file in the same spec line.
- Do not create a new workspace for every validation run or review pass.

## Stop Conditions

- If the owning spec or maintenance line is still unclear, return to `dev-flow-spec-driving` before creating anything.
- If the current workspace already satisfies the ownership rule, stop and reuse it instead of creating another one.

## Example

- Continue using the current workspace while implementing multiple sequential slices of the same spec.
- Start a different workspace before editing when the next request belongs to another spec, another branch of work, or unrelated cleanup.
