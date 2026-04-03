---
name: firebreak-runtime-profile
description: "Use when Firebreak behavior depends on local interactive VM flows versus cloud non-interactive job flows."
---

# Firebreak Runtime Profile

Choose one runtime mode before planning the slice.

## Modes

- Local: use [references/local.md](references/local.md) for developer-machine behavior.
- Cloud: use [references/cloud.md](references/cloud.md) for orchestrated job behavior.

## Workflow

1. Choose `Local` when the slice depends on interactive VM behavior, local ergonomics, or manual shell access.
2. Choose `Cloud` when the slice targets prepared inputs, one-shot jobs, or artifact-driven non-interactive execution.
3. If the slice truly spans both modes, split it into separate slices unless the change is explicitly about cross-mode behavior.

## Rules

- Do not import local affordances into cloud jobs.
- Do not degrade local UX with cloud-only constraints unless the slice explicitly targets both.
- State the chosen mode before selecting validation or implementation steps.

## Example

- Choose `Local` for work that depends on an interactive development VM or manual shell iteration.
- Choose `Cloud` for work that runs from prepared inputs and should complete as a non-interactive job with recorded artifacts.
