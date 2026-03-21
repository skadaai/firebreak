---
name: firebreak-change-loop
description: Use when a Firebreak task is larger than a trivial one-line fix. This skill enforces the bounded loop: frame the slice, record the plan, validate, review, then commit or block.
---

# Firebreak Change Loop

Follow the loop in order. Do not skip stages because the change looks small.

## Loop

1. Bind the attempt to a spec, explicit task, or bounded maintenance action.
2. Record one slice plan before substantial edits.
3. Keep the slice narrow enough to validate and review in one pass.
4. Run the required Firebreak validation suites.
5. Run a review pass on the resulting diff and artifacts.
6. Commit only if the slice is complete and evidence-backed.
7. Otherwise stop with `blocked` or `failed`.

## Rules

- Do not widen the slice mid-run without updating the plan.
- Do not claim success on intuition alone; use harness evidence.
- If validation cannot run, treat that as `blocked`, not success.
- If review finds unresolved critical issues, do not commit.
