---
status: completed
last_updated: 2026-03-23
---

# 007 Status

## Current phase

Implemented and validated.

## What has landed

- the top-level CLI now routes plumbing through `firebreak internal ...`
- the host-side isolated workspace concept is named `task` in the CLI and machine-readable output
- internal packages now use the `firebreak-internal-` prefix
- smoke packages and smoke checks now use the `firebreak-test-smoke-` prefix
- docs, workflows, and agent guidance now reference the new command and naming contract

## What remains open

- optional future promotion of human-facing commands such as `init`, `doctor`, and `run`
- optional renaming of internal-only NixOS configuration identifiers such as `firebreak-cloud-smoke`

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-23: Spec created to govern the human/internal CLI split, the `task` rename, and the package/test naming migration.
- 2026-03-23: Implemented the CLI split, task rename, package/check renames, test renames, and related doc updates.
