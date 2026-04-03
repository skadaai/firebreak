---
name: firebreak-change-loop
description: "Use when an autonomous slice is larger than a trivial one-line fix. This skill enforces the bounded loop: frame the attempt, record the plan, validate, review, then commit or block."
---

# Firebreak Change Loop

Follow the loop in order. Do not skip stages because the change looks small.

## Order

The normal sequence is: choose the slice with `firebreak-spec-driving`, choose or confirm the workspace with `firebreak-work-task`, enforce scope with `firebreak-boundaries`, then run this loop through validation and review.

## Loop

1. Bind the attempt to a spec, an explicit workspace, or bounded maintenance action.
2. If a spec is involved, update the existing contract unless the work genuinely needs a new one.
3. Reuse the current workspace for sequential work on the same spec; use a different workspace when the work moves to a different spec or unrelated line.
4. Record one slice plan before substantial edits.
5. Keep the slice narrow enough to validate and review in one pass.
6. Run the required Firebreak validation suites.
7. Run a review pass on the resulting diff and artifacts.
8. Commit only if the slice is complete and evidence-backed.
9. Otherwise stop with `blocked` or `failed`.

## Rules

- Do not widen the slice mid-run without updating the plan.
- Do not create a new spec just to track a small refinement of an existing contract.
- Do not claim success on intuition alone; use harness evidence.
- If validation cannot run, treat that as `blocked`, not success.
- If review finds unresolved critical issues, do not commit.
