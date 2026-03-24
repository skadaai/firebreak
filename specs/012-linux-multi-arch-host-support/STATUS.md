---
status: draft
last_updated: 2026-03-24
---

# 012 Status

## Current phase

Specification drafted. No implementation work has landed.

## What has landed

- a tracked spec, plan, and status record for expanding Firebreak local host support from `x86_64-linux` to include `aarch64-linux`

## What remains open

- flake refactor for host-system and guest-system separation
- runner compatibility changes for architecture-aware CPU and acceleration behavior
- launcher, diagnostics, validation, and smoke updates
- documentation and CI updates for the supported Linux host matrix

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec in response to the conclusion that Linux multi-arch host support is substantial enough to require its own tracked changeset before implementation.
