---
status: in_progress
last_updated: 2026-03-24
---

# 015 Status

## Current phase

Initial implementation in progress.

## What has landed

- a tracked spec, plan, and status record for host-brokered orchestrated agents
- a durable decision that `firebreak` workers should be host-brokered sibling VMs rather than guest-launched nested VMs
- a first-pass backend model with `process` and `firebreak`
- a host-side broker surface under `firebreak internal agent` with `spawn`, `list`, `show`, and `stop`
- a first worker-state model with stable worker ids, per-worker metadata, and host-owned runtime paths
- smoke coverage for the broker lifecycle and the CLI route into `firebreak internal agent`

## What remains open

- guest bridge implementation
- worker-kind declaration interface for external recipes
- first integration against an external orchestrator recipe
- richer lifecycle behavior such as worker reuse, log streaming, and cleanup policy
- docs for orchestration lifecycle behavior

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec after deciding that orchestrated agent fan-out needs a Firebreak-native contract instead of ad hoc process spawning or guest-launched nested virtualization.
- 2026-03-24: Landed the first host-broker slice with `firebreak internal agent`, worker metadata, `process` and `firebreak` backend spawning, and focused smoke coverage.
