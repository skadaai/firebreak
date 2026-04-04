---
status: completed
last_updated: 2026-03-25
---

# 009 Status

## Current phase

Implemented.

## What has landed

- `.firebreak.env` discovery and allowlisted public-key loading are implemented for the human-facing Firebreak surface
- agent-specific selectors now override generic selectors for their matching local workloads
- `host` mode now resolves through one shared host root with stable per-agent subdirectories for Codex and Claude Code
- `host` is now the default local config mode so first launch adopts existing home config into the shared host root when applicable
- `workspace` mode now remains project-local for dedicated local workloads instead of being redirected into the shared host root
- `firebreak init` writes a minimal Firebreak-native project defaults template
- `firebreak doctor` reports summary, verbose, and JSON diagnostics for project config and local readiness
- the local wrapper now uses `FIREBREAK_LAUNCH_MODE` as the only public local mode selector
- a dedicated smoke package covers the config/init/doctor contract

## What remains open

- none in this changeset

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to define the Firebreak-native project config, bootstrap, and diagnostics contract without importing legacy sandbox migration behavior.
- 2026-03-23: Implemented `.firebreak.env` loading, `firebreak init`, `firebreak doctor`, public allowlisting, selector precedence, and smoke coverage.
- 2026-03-25: Unified local `host` mode on one shared host root with stable `codex` and `claude` subdirectories, and removed per-agent host-path variables from the public config surface.
