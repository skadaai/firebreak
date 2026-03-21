---
name: firebreak-spec-driving
description: "Use when work starts from a Firebreak spec or an underspecified request. This skill turns the spec into the next thin execution slice with matching write scope and validation."
---

# Firebreak Spec Driving

Drive from the next slice, not from the whole spec.

## Workflow

1. Read only the relevant spec and nearby code.
2. Choose the next slice that can land independently.
3. Name the expected file scope and validation before editing.
4. Prefer slices that tighten structure, harnesses, or contracts before optional polish.

## Rules

- Avoid slices that span many modules unless the spec explicitly requires it.
- If the right next slice is still ambiguous, narrow it further instead of guessing.
- Keep the slice small enough that a failed validation points to one thing.
