---
name: dev-flow-change-loop
description: "Use when an autonomous slice is larger than a trivial one-line fix. This skill enforces the bounded loop: frame the attempt, record the plan, validate, review, then commit or block."
---

# Dev Flow Change Loop

Follow the loop in order once the owning spec and workspace are already known. Do not use this skill to decide whether a new spec or workspace is needed.

## Inputs

- one bounded slice with an owning spec or maintenance line
- one explicit workspace decision
- one expected validation set and write scope

## Outputs

- one attempt record with plan, validation evidence, review result, and final disposition
- one of: `completed`, `blocked`, or `failed`

## Order

The normal sequence is: `dev-flow-spec-driving` chooses the slice, `dev-flow-workspace` chooses the workspace, `dev-flow-boundaries` fixes scope, then this skill drives execution through validation and review.

## Loop

1. Bind the attempt to a spec, explicit workspace, or bounded maintenance action.
2. Record one slice plan before substantial edits.
3. Keep the slice narrow enough to validate and review in one pass.
4. Run the required named validation suites.
5. Run a review pass on the resulting diff and artifacts.
6. Commit only if the slice is complete and evidence-backed.
7. Otherwise stop with `blocked` or `failed`.

## Rules

- Do not widen the slice mid-run without updating the plan.
- Do not claim success on intuition alone; use harness evidence.
- If validation cannot run, treat that as `blocked`, not success.
- If review finds unresolved critical issues, do not commit.

## Stop Conditions

- If the work no longer fits the selected spec or workspace, return to `dev-flow-spec-driving` or `dev-flow-workspace` instead of widening the current attempt.
- If the attempt needs validation that was not named up front, stop and update the slice contract before continuing.
