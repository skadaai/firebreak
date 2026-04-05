---
status: completed
last_updated: 2026-04-04
---

# 016 Status

## Current phase

Implemented.

## What has landed

- native project config is now treated as part of the mounted workspace rather than as Firebreak-managed runtime state
- `host`, `workspace`, `vm`, and `fresh` now select runtime state roots instead of Firebreak-owned project overlays
- shared runtime-state resolution is implemented for dedicated Codex and Claude Code VMs and for shared wrapper-based sandboxes
- opt-in credential-slot adapters now support file bindings, env bindings, helper bindings, and slot-first login materialization
- Codex and Claude Code now declare initial credential-slot adapters, and a dedicated credential-fixture package covers the shared adapter contract
- dedicated Codex and Claude Code wrapper integration smokes now validate the real package wrappers against selected slots, per-tool slot overrides, and slot-root login materialization without relying on browser OAuth
- project config loading, `firebreak init`, `firebreak doctor`, and user-facing docs now explain state roots and credential slots explicitly
- focused automated validation now covers runtime-state resolution, shared credential slots, login-to-slot materialization, and multi-tool slot overrides

## What remains open

- broader package adoption beyond the first Codex, Claude Code, and fixture adapters
- future UX helpers for creating or importing credential-slot contents

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)
- [acceptance/VALIDATION.md](./acceptance/VALIDATION.md)

## History

- 2026-04-04: Spec created to replace the current conflated config model with a cleaner split between native project config, Firebreak-managed runtime state, and opt-in credential-slot injection.
- 2026-04-04: Implemented shared runtime-state roots, slot-based credential adapters, slot-first login materialization, diagnostics, docs, and automated validation for the first landing.
