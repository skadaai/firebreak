---
name: dev-flow-autonomous-flow
description: "Use when starting or resuming non-trivial autonomous work in this repository. This skill coordinates spec selection, workspace choice, boundaries, validation, and review around the dev-flow workspace model."
---

# Dev Flow Autonomous Flow

Use this as the top-level skill for non-trivial autonomous work in this branch. Prefer it over manually composing lower-level skills unless the task is obviously limited to one narrow phase.

## Inputs

- a user request, spec change, or maintenance task that is larger than a trivial edit
- the current workspace context, if one already exists
- the expected runtime mode when local versus cloud behavior matters

## Outputs

- one owning spec or maintenance line
- one next bounded slice
- one workspace decision: reuse current workspace or create/resume another workspace
- one expected validation set and review path
- one explicit stop reason when the work cannot safely proceed

## Sequence

1. Use `dev-flow-spec-driving` to identify the owning spec and next independent slice.
2. Use `dev-flow-workspace` to decide whether to reuse the current workspace or start another one.
3. Use `dev-flow-boundaries` to declare write scope and shared-path limits before editing.
4. Use `dev-flow-runtime-profile` before planning when local versus cloud behavior matters.
5. Use `dev-flow-change-loop` to keep the slice bounded and evidence-backed.
6. Use `dev-flow-validation` to gather machine-readable evidence.
7. Use `dev-flow-review` before commit or handoff.

## Workspace Rules

- Reuse the current workspace for sequential work on the same spec.
- Start a separate workspace when the work moves to a different spec or unrelated maintenance line.
- Do not edit the primary checkout for autonomous implementation work.

## Command Surface

- Use `dev-flow workspace ...` to create, inspect, and close workspaces.
- Use `dev-flow validate run ...` for named validation suites.
- Use `dev-flow loop run ...` only after the slice, workspace, and validation suites are explicit.
- For concrete command shapes, see [references/commands.md](references/commands.md).
- For workspace and branch naming shapes, see [references/naming.md](references/naming.md).

## Stop Conditions

- If the owning spec is unclear, narrow the slice before editing.
- If write scope or shared-path ownership is unclear, stop before editing.
- If no suitable validation suite exists, record the gap instead of claiming success.
