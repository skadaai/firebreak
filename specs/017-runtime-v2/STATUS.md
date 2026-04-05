---
status: draft
last_updated: 2026-04-05
---

# 017 Runtime V2 Status

## Current phase

Drafting the runtime replacement contract.

## What is landed

- the repository now records an explicit anti-degradation and anti-compatibility-layer rule in [AGENTS.md](../../AGENTS.md)
- Runtime v2 is defined as a profile-stable, backend-private replacement effort rather than a conservative migration

## What remains open

- backend capability contract implementation
- Linux local Cloud Hypervisor runtime implementation
- Linux local port publishing replacement for the current QEMU-specific forwarding path
- deletion of Linux local QEMU support after replacement lands
- future cloud backend selection and implementation

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)
- [AGENTS.md](../../AGENTS.md)

## History

- 2026-04-05: created Runtime v2 as a new design-definition changeset centered on aggressive replacement rather than compatibility-preserving migration
