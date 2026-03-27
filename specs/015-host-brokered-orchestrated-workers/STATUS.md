---
status: in_progress
last_updated: 2026-03-27
---

# 015 Status

## Current phase

Reopened for attached `firebreak` worker hardening and guest lifecycle observability.

## What has landed

- a tracked spec, plan, and status record for host-brokered orchestrated workers
- a durable decision that `firebreak` workers should be host-brokered sibling VMs rather than guest-launched nested VMs
- a first-pass backend model with `process` and `firebreak`
- a host-side broker surface under `firebreak worker` with `run`, `ps`, `inspect`, `logs`, `stop`, `rm`, and `prune`
- a first worker-state model with stable worker ids, per-worker metadata, and host-owned runtime paths
- smoke coverage for the broker lifecycle and the CLI route into `firebreak worker`
- a local-profile guest bridge that mounts a request-response share and exposes guest-visible `firebreak worker ...` forwarding inside bridge-enabled orchestrator VMs
- focused VM smoke coverage proving a guest can call the worker surface through that bridge
- guest-local `process` worker semantics through a guest-owned worker state directory and the same `firebreak worker` surface
- first worker-kind declarations in bridge-enabled VMs so a guest can resolve kinds to `process` or `firebreak` without raw backend flags
- per-kind bounded concurrency through `max_instances` in worker-kind declarations
- first recipe-level worker-kind declarations in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
- generic packaged-node-cli support for declarative extra bin scripts
- a generic packaged-node bootstrap-readiness helper (`firebreak-bootstrap-wait`) for recipe-owned validation and wrapper probing
- a reusable Firebreak worker-proxy script helper for external recipes that want a CLI name to resolve through `firebreak worker`
- a recipe-owned smoke path in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) for validating bootstrap readiness and worker-proxy wrapper installation without moving orchestrator logic into Firebreak core
- a recipe-owned smoke path in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) for real declared-worker creation through the guest-visible `firebreak worker` surface
- the attached execution contract has been identified as the remaining weak spot inside the `firebreak` backend rather than in worker-kind declaration or detached worker lifecycle plumbing
- attached sibling-worker transport now exposes request-level bridge traces, live nested runtime traces, and streamed boot output back into the orchestrator guest
- packaged Bun-agent bootstrap now emits explicit machine-readable bootstrap phases and avoids recursive ownership fixups during startup
- `firebreak worker debug` now surfaces machine-readable guest bootstrap and command state when packaged-cli workers publish them through the exec-output mount
- direct packaged-cli readiness smokes now preserve reviewable runtime evidence long enough to assert guest lifecycle artifacts instead of relying only on terminal output
- the direct packaged-cli readiness path now waits for guest bootstrap readiness before one-shot agent commands execute, so `--version` probes no longer race bootstrap

## What remains open

- a validated attached `codex` proxy path through the external orchestrator recipe after the nested guest bootstrap path is fully reviewable
- richer lifecycle behavior such as worker reuse, log filtering, and cleanup policy refinements
- possible transport hardening beyond the first file-share bridge, such as a mounted Unix-socket protocol
- broader recipe adoption and validation beyond the first external orchestrator recipe

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
- 2026-03-26: Reworked the public worker CLI around `run`, `ps`, `inspect`, `logs`, `stop`, `rm`, and `prune`, made default listing concise, and added worker cleanup semantics.
- 2026-03-26: Confirmed the first external orchestrator recipe manually in a real runtime: guest-visible worker execution, host-owned worker state, concise listing, cleanup, and bounded concurrency all behaved as specified.
- 2026-03-26: Reopened the spec after confirming that attached sibling-worker execution for interactive `firebreak` workers is still incomplete even though detached lifecycle behavior and manual detached validation already passed.
- 2026-03-27: Added bridge-level attach diagnostics, streamed nested runner output, guest-visible attach progress, and packaged Bun-agent bootstrap phase markers so attached-worker failures can be diagnosed without raw host-side process archaeology.
