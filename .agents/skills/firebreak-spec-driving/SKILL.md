---
name: firebreak-spec-driving
description: "Use when work starts from a Firebreak spec or an underspecified request. This skill decides whether to amend an existing spec or create a new one, then turns the contract into the next thin execution slice."
---

# Firebreak Spec Driving

Drive from the durable contract, then choose the next slice.

## Workflow

1. Read the relevant existing spec and nearby code first.
2. Decide whether the change belongs under that existing contract or truly needs a new spec.
3. Keep `SPEC.md` timeless; put "now vs then" in `PLAN.md` or `STATUS.md`.
4. Choose the next slice that can land independently.
5. Name the expected file scope and validation before editing.

## Rules

- Prefer amending an existing spec when the durable contract is unchanged.
- Create a new spec only when the work introduces a distinct durable contract, a distinct decision, or a truly independent changeset.
- Avoid slices that span many modules unless the spec explicitly requires it.
- If the right next slice is still ambiguous, narrow it further instead of guessing.
- Keep the slice small enough that a failed validation points to one thing.
