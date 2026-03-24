---
status: completed
last_updated: 2026-03-23
---

# 009 Status

## Current phase

Implemented.

## What has landed

- `.firebreak.env` discovery and allowlisted public-key loading are implemented for the human-facing Firebreak surface
- agent-specific selectors now override generic selectors for their matching local workloads
- `firebreak init` writes a minimal Firebreak-native project defaults template
- `firebreak doctor` reports summary, verbose, and JSON diagnostics for project config and local readiness
- the local wrapper now uses `FIREBREAK_VM_MODE` as the only public local mode selector
- a dedicated smoke package covers the config/init/doctor contract

## What remains open

- none in this changeset

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to define the Firebreak-native project config, bootstrap, and diagnostics contract without importing legacy sandbox migration behavior.
- 2026-03-23: Implemented `.firebreak.env` loading, `firebreak init`, `firebreak doctor`, public allowlisting, selector precedence, and smoke coverage.
