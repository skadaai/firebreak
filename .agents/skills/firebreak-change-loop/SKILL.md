---
name: firebreak-change-loop
description: "Use when an autonomous slice is larger than a trivial one-line fix. This skill enforces the bounded loop: frame the attempt, record the plan, validate, review, then commit or block."
---

# Firebreak Change Loop

Follow the loop in order. Do not skip stages because the change looks small.

## Loop

1. Bind the attempt to a spec, explicit workspace, or bounded maintenance action.
2. If a spec is involved, update the existing contract unless the work genuinely needs a new one.
3. Record one slice plan before substantial edits.
4. Keep the slice narrow enough to validate and review in one pass.
5. Run the required Firebreak validation suites.
6. Run a review pass on the resulting diff and artifacts.
7. Commit only if the slice is complete and evidence-backed.
8. Otherwise stop with `blocked` or `failed`.

## Rules

- Do not widen the slice mid-run without updating the plan.
- Do not create a new spec just to track a small refinement of an existing contract.
- Do not claim success on intuition alone; use harness evidence.
- If validation cannot run, treat that as `blocked`, not success.
- If review finds unresolved critical issues, do not commit.
