---
name: dev-flow-validation
description: "Use when a workspace-backed change attempt needs evidence before completion, handoff, or commit. This skill selects named validation suites and classifies outcomes as passed, failed, or blocked."
---

# Dev Flow Validation

Use the dev-flow harness, not ad hoc shell output, as the source of truth.

## Inputs

- one bounded slice
- one named validation target or smallest candidate suite
- one workspace-backed diff or attempt under test

## Outputs

- `suite`
- `result`
- `required_capabilities`
- `missing_capability`
- `command`
- `run_dir`
- `stdout_path`
- `stderr_path`
- `exit_code_path`
- `started_at`
- `finished_at`
- `exit_code`

## Order

Use this skill after the slice is implemented and the expected scope is known. Feed its result into `dev-flow-review` instead of treating raw shell output as sufficient evidence.

## Workflow

1. Pick the smallest named suite that proves the slice.
2. Run it through the current named validation entrypoint, for example `dev-flow validate run`.
3. Read the emitted `result`, command, capability fields, and output paths.
4. Decide the next action from the emitted result.

## Outcomes

- `passed`: the selected evidence is good enough to proceed.
- `failed`: the change or fixture is wrong; fix it or stop.
- `blocked`: the host, policy, or capability prevented a valid run.

## Rules

- Prefer narrower suites before broader suites.
- Do not replace a missing suite with “I ran something similar” and call it complete.
- If no suitable suite exists, report a validation gap instead of pretending success.
- Preserve the validation summary and artifacts for review.

## Stop Conditions

- If no named suite can prove the slice, stop and record a validation gap.
- If the result is `blocked`, stop and report the blocking capability or policy instead of guessing.
