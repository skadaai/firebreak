---
name: firebreak-runtime-profile
description: Use when Firebreak behavior depends on local interactive VM flows versus cloud non-interactive job flows. Read only the reference for the selected runtime mode.
---

# Firebreak Runtime Profile

Choose one runtime mode before planning the slice.

## Modes

- Local: use [references/local.md](references/local.md) for developer-machine behavior.
- Cloud: use [references/cloud.md](references/cloud.md) for orchestrated job behavior.

## Rules

- Do not import local affordances into cloud jobs.
- Do not degrade local UX with cloud-only constraints unless the task explicitly targets both.
- If a task truly spans both modes, split it into separate slices whenever possible.
