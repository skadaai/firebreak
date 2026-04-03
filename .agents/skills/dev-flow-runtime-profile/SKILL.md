---
name: dev-flow-runtime-profile
description: "Use when dev-flow behavior depends on local interactive VM flows versus cloud non-interactive job flows."
---

# Dev Flow Runtime Profile

Choose one runtime mode before planning the slice.

## Inputs

- one bounded slice
- whether the work depends on interactive local behavior or non-interactive cloud execution

## Outputs

- `runtime_mode`
- mode-specific validation expectations
- mode-specific command and artifact expectations

## Modes

- Local: use [references/local.md](references/local.md) for developer-machine behavior.
- Cloud: use [references/cloud.md](references/cloud.md) for orchestrated job behavior.

## Workflow

1. Choose `Local` when the slice depends on interactive VM behavior, local ergonomics, or manual shell access.
2. Choose `Cloud` when the slice targets prepared inputs, one-shot jobs, or artifact-driven non-interactive execution.
3. If the slice truly spans both modes, split it into separate slices unless the change is explicitly about cross-mode behavior.

## Consequences

- `Local`: prefer validation and commands that assume an interactive workspace and developer-machine shell access.
- `Cloud`: prefer validation and commands that assume prepared inputs, non-interactive execution, and recorded job artifacts.

## Rules

- Do not import local affordances into cloud jobs.
- Do not degrade local UX with cloud-only constraints unless the slice explicitly targets both.
- State the chosen mode before selecting validation or implementation steps.

## Stop Conditions

- If the slice would require both modes for ordinary completion work, split it before implementation.
- If the chosen mode changes the validation story materially, restate the slice contract before continuing.

## Example

- Choose `Local` for work that depends on an interactive development VM or manual shell iteration.
- Choose `Cloud` for work that runs from prepared inputs and should complete as a non-interactive job with recorded artifacts.
