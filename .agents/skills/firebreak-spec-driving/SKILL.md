---
name: firebreak-spec-driving
description: "Use when work starts from a Firebreak spec or an underspecified request. This skill decides whether to amend an existing spec or create a new one, then turns the contract into the next thin execution slice."
---

# Firebreak Spec Driving

Drive from the durable contract, then choose the next slice.

## Order

Use this skill before `firebreak-work-task` and `firebreak-change-loop`. First decide the owning spec and next slice, then decide whether that slice stays in the current workspace or needs a separate workspace.

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

## Example

- If the current workspace is implementing `specs/007-cli-and-naming-contract` and the next change still belongs to that contract, keep using the same workspace.
- If the next requested change belongs to a different spec or a distinct maintenance line, hand it off to `firebreak-work-task` as a separate workspace decision.
