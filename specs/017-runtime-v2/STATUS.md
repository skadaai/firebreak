---
status: draft
last_updated: 2026-04-05
---

# 017 Runtime V2 Status

## Current phase

Executing the Linux local runtime replacement and cold-boot reduction slices.

## What is landed

- the repository now records an explicit anti-degradation and anti-compatibility-layer rule in [AGENTS.md](../../AGENTS.md)
- Runtime v2 is defined as a profile-stable, backend-private replacement effort rather than a conservative migration
- runtime backends now have an explicit capability contract consumed by product profiles
- Linux local Firebreak now defaults to Cloud Hypervisor and rejects the superseded local QEMU path
- Linux local networking and host port publishing now exist as Cloud Hypervisor-specific host plumbing rather than QEMU `hostfwd`
- local networking capabilities are now split more honestly; launcher-level Linux host-network preflight is gone, and Cloud Hypervisor host networking setup no longer runs unless a workload actually requests it
- local tool bootstrapping has been moved further off the hot path through baked CLIs and bootstrap skip conditions
- Linux local `/nix/store` and host metadata now use `virtiofs` rather than Linux `9p`
- local share startup has been simplified by collapsing host metadata, exec-output, and worker-bridge into one writable runtime share
- local `virtiofsd` startup is now parallelized rather than serialized
- shared state-root and credential-slot mounts now fail fast instead of silently downgrading
- local non-interactive command requests now have an explicit request/response contract instead of boot-time metadata smearing
- Linux local now has a private warm instance controller and guest command-agent mode for repeated `agent-exec` reuse
- warm local controller requests are now serialized per instance, stale warm daemons are invalidated on build changes, and controller lifecycle tracing exists in the wrapper logs
- the runtime now has a cheap host-side warm-controller smoke suite that can be run through flake checks and internal validation without booting a VM
- the runtime now also exposes a real `test-smoke-codex-warm-reuse` suite for repeated stable local commands against one controller-owned VM lifetime

## What remains open

- execution and hardening of the new warm local `agent-exec` reuse smoke on a prepared Linux host
- warm attached command dispatch for `agent-attach-exec`
- snapshot preparation and restore on the local Cloud Hypervisor backend
- deletion of remaining stale runtime assumptions and warnings that no longer fit the accepted backend contract
- future cloud backend selection and implementation

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)
- [AGENTS.md](../../AGENTS.md)

## History

- 2026-04-05: created Runtime v2 as a new design-definition changeset centered on aggressive replacement rather than compatibility-preserving migration
- 2026-04-05: landed backend capability checks, Linux local Cloud Hypervisor cutover, local networking/port publishing, hot-path bootstrap reduction, runtime-share consolidation, fail-fast share semantics, explicit command requests, a guest warm command-agent mode, a private local warm instance controller, controller serialization and stale-build invalidation, and a cheap host-side warm-controller smoke suite
