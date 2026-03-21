---
name: firebreak-validation
description: Use when a Firebreak task needs evidence before completion, handoff, or commit. This skill selects named Firebreak validation suites and classifies outcomes as passed, failed, or blocked.
---

# Firebreak Validation

Use the Firebreak harness, not ad hoc shell output, as the source of truth.

## Workflow

1. Pick the smallest named suite that proves the slice.
2. Run it through `firebreak validate`.
3. Read the machine result and artifact paths.
4. Decide the next action from the result.

## Outcomes

- `passed`: the selected evidence is good enough to proceed.
- `failed`: the change or fixture is wrong; fix it or stop.
- `blocked`: the host, policy, or capability prevented a valid run.

## Rules

- Prefer narrower suites before broader suites.
- Do not replace a missing suite with “I ran something similar” and call it complete.
- If no suitable suite exists, report a validation gap instead of pretending success.
- Preserve the validation summary and artifacts for review.
