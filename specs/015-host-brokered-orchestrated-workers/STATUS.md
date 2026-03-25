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
- guest-local `process` worker semantics through a guest-owned worker state directory and the same `firebreak worker` nouns
- first worker-kind declarations in bridge-enabled VMs so a guest can resolve kinds to `process` or `firebreak` without raw backend flags
- per-kind bounded concurrency through `max_instances` in worker-kind declarations
- first recipe-level worker-kind declarations in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
- generic packaged-node-cli support for declarative extra bin scripts
- a generic packaged-node bootstrap-readiness helper (`firebreak-bootstrap-wait`) for recipe-owned validation and wrapper probing
- a reusable Firebreak worker-proxy script helper for external recipes that want a CLI name to resolve through `firebreak worker`
- a recipe-owned smoke path in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) for validating bootstrap readiness and worker-proxy wrapper installation without moving orchestrator logic into Firebreak core

## What remains open

 - fully passing end-to-end validation for real worker creation from the first external orchestrator recipe
 - richer lifecycle behavior such as worker reuse, log streaming, and cleanup policy
 - focused runtime validation for declared `firebreak` worker kinds through the guest-visible orchestrator path

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec after deciding that orchestrated worker fan-out needs a Firebreak-native contract instead of ad hoc process spawning or guest-launched nested virtualization.
- 2026-03-24: Landed the first host-broker slice with `firebreak worker`, worker metadata, `process` and `firebreak` backend spawning, and focused smoke coverage.
- 2026-03-25: Promoted the broker surface from maintainer-only `internal` naming to the top-level public `worker` command and aligned the slice vocabulary around workers instead of agents.
- 2026-03-25: Landed the first guest-bridge slice for local orchestrator VMs with a mounted request-response channel, guest-visible `firebreak worker` forwarding, and focused bridge smoke coverage.
- 2026-03-25: Split worker execution authority cleanly so declared `process` workers are guest-local while declared `firebreak` workers stay host-brokered, and added recipe-level worker-kind declarations.
- 2026-03-25: Added generic packaged-node-cli support for declarative extra bin scripts and a reusable worker-proxy helper so external recipes can route selected CLI names through `firebreak worker` without adding orchestrator-specific code to Firebreak's shared layers.
- 2026-03-25: Added a generic packaged-node bootstrap-readiness helper, bounded per-kind concurrency via `max_instances`, and a recipe-owned validation path for the first external orchestrator recipe.
