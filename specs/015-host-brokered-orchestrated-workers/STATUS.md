---
status: in_progress
last_updated: 2026-03-25
---

# 015 Status

## Current phase

Initial implementation in progress.

## What has landed

- a tracked spec, plan, and status record for host-brokered orchestrated workers
- a durable decision that `firebreak` workers should be host-brokered sibling VMs rather than guest-launched nested VMs
- a first-pass backend model with `process` and `firebreak`
- a host-side broker surface under `firebreak worker` with `spawn`, `list`, `show`, and `stop`
- a first worker-state model with stable worker ids, per-worker metadata, and host-owned runtime paths
- smoke coverage for the broker lifecycle and the CLI route into `firebreak worker`
- a local-profile guest bridge that mounts a request-response share and exposes guest-visible `firebreak worker ...` forwarding inside bridge-enabled orchestrator VMs
- focused VM smoke coverage proving a guest can call the worker surface through that bridge

## What remains open

- guest bridge implementation for shared-guest `process` worker semantics
- worker-kind declaration interface for external recipes
- first integration against an external orchestrator recipe
- richer lifecycle behavior such as worker reuse, log streaming, and cleanup policy
- docs for orchestration lifecycle behavior

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec after deciding that orchestrated worker fan-out needs a Firebreak-native contract instead of ad hoc process spawning or guest-launched nested virtualization.
- 2026-03-24: Landed the first host-broker slice with `firebreak worker`, worker metadata, `process` and `firebreak` backend spawning, and focused smoke coverage.
- 2026-03-25: Promoted the broker surface from maintainer-only `internal` naming to the top-level public `worker` command and aligned the slice vocabulary around workers instead of agents.
- 2026-03-25: Landed the first guest-bridge slice for local orchestrator VMs with a mounted request-response channel, guest-visible `firebreak worker` forwarding, and focused bridge smoke coverage.
