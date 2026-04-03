---
name: dev-flow-spec-driving
description: "Use when work starts from a repo spec or an underspecified request. This skill decides whether to amend an existing spec or create a new one, then turns the contract into the next thin execution slice."
---

# Dev Flow Spec Driving

Drive from the durable contract, then choose the next slice.

## Inputs

- a user request, bug report, reviewer finding, or spec-driven follow-up
- relevant existing specs and nearby code
- the current workspace context, if one already exists

## Outputs

- `owning_spec`: the existing spec to amend, a new spec to create, or `maintenance`
- `next_slice`: one independently landable unit of work
- `workspace_decision`: stay in the current workspace or move to another one
- `expected_validation`: the smallest suites expected to prove the slice

## Order

Use this skill before `dev-flow-workspace` and `dev-flow-change-loop`. First decide the owning spec and next slice, then decide whether that slice stays in the current workspace or needs a separate workspace.

## Workflow

1. Read the relevant existing spec and nearby code first.
2. Decide whether the change belongs under that existing contract or truly needs a new spec.
3. Keep `SPEC.md` timeless; put "now vs then" in `PLAN.md` or `STATUS.md`.
4. Choose the next slice that can land independently.
5. State whether the slice belongs in the current workspace or requires a different workspace because it belongs to a different spec or unrelated line.
6. Name the expected file scope and validation before editing.

## Rules

- Prefer amending an existing spec when the durable contract is unchanged.
- Create a new spec only when the work introduces a distinct durable contract, a distinct decision, or a truly independent changeset.
- Avoid slices that span many modules unless the spec explicitly requires it.
- If the right next slice is still ambiguous, narrow it further instead of guessing.
- Keep the slice small enough that a failed validation points to one thing.

## Anti-Patterns

- Do not create a new spec for a small refinement of an existing contract.
- Do not choose a slice that spans unrelated specs just because the files are nearby.
- Do not defer the workspace decision until after editing has started.

## Stop Conditions

- If more than one spec plausibly owns the change, stop and resolve ownership before editing.
- If the next slice cannot be named without “and also”, narrow it further before handing off.

## Example

- If the current workspace is implementing `specs/007-cli-and-naming-contract` and the next change still belongs to that contract, keep using the same workspace.
- If the next requested change belongs to a different spec or a distinct maintenance line, hand it off to `dev-flow-workspace` as a separate workspace decision.
