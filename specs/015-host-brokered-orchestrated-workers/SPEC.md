---
status: in_progress
last_updated: 2026-03-28
---

# 015 Host-Brokered Orchestrated Workers

## Problem

Firebreak can already launch individual agent VMs, and external orchestrator recipes such as [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) can already run inside a Firebreak sandbox.

What Firebreak does not define yet is how an orchestrator inside one Firebreak VM should obtain more workers.

Today there are two obvious but incomplete answers:

- install every agent CLI inside the orchestrator VM and run them as regular processes
- let the orchestrator VM try to launch more VMs from inside itself

The first option collapses isolation, state boundaries, and resource accounting back into one guest. The second option fights Firebreak's current host-runner model and turns nested virtualization into an accidental product contract.

Without an explicit orchestration layer, Firebreak cannot give external orchestrators a stable, high-trust way to fan out work across isolated workers while preserving the current VM runtime boundaries.

## Affected users, actors, or systems

- maintainers designing external Firebreak recipes for agent orchestrators
- operators who want one orchestrator to fan out into many workers
- future Firebreak host-side schedulers or worker brokers
- existing Firebreak local-launch packages such as `firebreak-codex` and `firebreak-claude-code`

## Goals

- define a Firebreak-native orchestration contract above the current local VM runtime
- let an orchestrator request isolated sibling workers without needing to launch nested VMs from inside a guest
- support more than one worker execution backend, beginning with `process` and `firebreak`
- keep the guest-visible control surface stable even when the worker backend changes
- make worker lifecycle, state ownership, and concurrency limits explicit
- support both detached and attached worker execution semantics across the `process` and `firebreak` backends
- preserve real terminal semantics for attached `firebreak` workers so interactive CLIs can use sibling workers directly
- make packaged worker startup deterministic enough that attached interactive workers do not depend on ad hoc network installs during every boot

## Non-goals

- making guest-launched nested MicroVMs part of the Firebreak product contract
- distributed scheduling across multiple physical hosts
- unbounded autoscaling without operator-configured limits
- redesigning existing single-agent packages such as `firebreak-codex` or `firebreak-claude-code`
- defining every possible external orchestrator integration in the first changeset
- treating repeated boot-time package installation as the steady-state product contract for attached interactive workers

## Morphology and scope of the changeset

This changeset is structural and operational.

It introduces an orchestration layer above Firebreak's current VM packages.

The intended landing shape is:

- an orchestrator VM acts as a control plane
- a host-side Firebreak broker owns worker spawning and lifecycle
- the orchestrator guest talks to that host broker through a narrow Firebreak control surface instead of launching child VMs directly
- Firebreak defines worker backends, beginning with `process` and `firebreak`
- the `firebreak` backend launches sibling worker VMs on the host rather than nested worker VMs inside the guest
- external recipes can declare which worker kinds they expose and which backend each kind uses

## Requirements

- The system shall define a Firebreak orchestration contract for external orchestrator sandboxes.
- The system shall provide at least two worker execution backends: `process` and `firebreak`.
- When an orchestrator requests a `process` worker, the system shall run that worker inside the orchestrator VM under the shared guest runtime.
- When an orchestrator requests a `firebreak` worker, the system shall ask the host to launch a sibling Firebreak worker instead of asking the guest to launch a nested VM.
- The system shall not require guest-launched nested virtualization as part of the public orchestration contract.
- The system shall expose a guest-visible control surface for worker lifecycle operations such as spawn, status, list, and stop.
- The system shall keep that guest-visible control surface stable across worker backends.
- The system shall give each spawned worker a stable worker identifier and reviewable metadata.
- The system shall keep runner state, instance directories, temporary roots, and control sockets for `firebreak` workers under host-side ownership.
- The system shall allow external recipes to declare orchestratable worker kinds and the backend used for each kind.
- The system shall allow bounded per-kind or per-recipe concurrency limits.
- The system shall support attached worker execution for both the `process` and `firebreak` backends.
- When an attached `firebreak` worker runs through the host broker, the system shall preserve a real terminal path to the sibling worker instead of degrading it into a detached log-only job.
- The system shall provide focused validation and reviewable diagnostics for attached `firebreak` worker execution.
- The system shall publish machine-readable guest lifecycle state for attached `firebreak` workers, covering at least guest bootstrap progress and guest command progress.
- The system shall surface that machine-readable guest lifecycle state through `firebreak worker debug --json` so host-side diagnosis does not depend on truncated terminal logs.
- The system shall preserve reviewable attach trace events that distinguish first sibling-runner output from first post-`command-start` command output, even after the live bridge request directory is cleaned up.
- The system shall forward attached-terminal metadata to sibling workers only when that metadata is well-formed, including forwarding `LINES` and `COLUMNS` only when both are positive integers.
- The system shall surface the requested attached-terminal contract, including `TERM`, `LINES`, and `COLUMNS`, through `firebreak worker debug` for live review.
- The system shall preserve reviewable runtime artifacts for direct packaged-cli readiness probes when those probes fail.
- The system shall not require repeated network-backed package installation during the normal startup path for attached interactive workers once the packaged toolchain has been prepared successfully.
- The system shall provide a deterministic packaged-tool delivery path for attached interactive workers, either by baking tools into the image or by reusing a prepared host-owned shared tools state outside the critical interactive boot path.
- The system shall apply that deterministic packaged-tool delivery path to both Bun-managed and packaged node-cli worker images that participate in the orchestration flow.
- The system shall validate packaged-tool reuse with focused smokes before relying on slower end-to-end orchestrator validation.
- The system shall define how orchestrated workers resolve workspace access so the worker can act on the intended project state.
- The system shall define how orchestrated workers resolve Firebreak config modes and agent-specific config where those differ from the orchestrator VM.
- The system shall allow existing Firebreak single-agent packages to remain usable outside the orchestration layer.

## Recorded decisions

- The host-brokered sibling-worker architecture remains the intended product direction. The evidence collected during attached `codex` debugging confirms that the broker contract, attach transport, and nested command handoff are viable and should be retained.
- The current slow path, where attached interactive workers may spend most of their startup budget in boot-time `bun install --global @openai/codex@latest`, is not accepted as the steady-state design.
- AO end-to-end repros remain necessary as final integration checks, but they are no longer the primary debugging loop for attached packaged-worker startup. Focused direct readiness and reuse validation must lead.
- The current effort is therefore reframed as a deterministic packaged-tool delivery problem inside the still-valid host-brokered worker architecture, rather than as a generic attach-transport problem.
- Attached worker relay stability now depends on a direct PTY driver rather than shelling through `script` as the primary transport primitive.
- Focused interactive validation shall use an isolated synthetic worker and preserved runtime artifacts so attach regressions can be diagnosed without depending on the external orchestrator recipe.
- External orchestrator recipe smokes should validate packaged worker behavior through a no-forward test variant whenever host port forwarding is not part of the behavior under test.

## Acceptance criteria

- Firebreak has an explicit orchestration contract that distinguishes `process` workers from `firebreak` workers.
- The `firebreak` worker path is defined as host-brokered sibling VM launch rather than guest-launched nested virtualization.
- A guest-visible control surface exists for worker lifecycle operations without exposing raw host runner internals.
- External recipe authors have a defined way to register worker kinds, worker backends, and concurrency limits.
- Attached `firebreak` workers can be validated through a focused runtime path that proves interactive sibling-worker execution instead of only detached worker creation.
- Attached `firebreak` workers expose reviewable machine-readable guest lifecycle state that identifies the last bootstrap and command phases reached.
- External packaged-cli recipes have a defined bootstrap-readiness contract and can install recipe-owned worker-proxy wrappers without modifying Firebreak core.
- Worker identity, lifecycle state, and host-owned runtime paths are explicit and reviewable.
- The first integration path can target an external orchestrator recipe such as [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) without changing the public names of existing single-agent packages.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [spec 005](../005-isolated-work-tasks/SPEC.md)
- [spec 008](../008-single-agent-package-mode/SPEC.md)
- [spec 009](../009-project-config-and-doctor/SPEC.md)
- current [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- current [nix/support/projects.nix](../../nix/support/projects.nix)
- current [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)

### Risks

- a weak orchestration boundary could leak host-runner internals into guest-facing product surface
- worker workspace semantics could drift if orchestrator-visible paths and worker-visible paths are not aligned explicitly
- process and VM backends could diverge semantically if the control surface is not kept intentionally narrow
- a premature scheduler design could overreach before one local host-brokered integration is proven

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
- [README.md](../../README.md)
- [UPSTREAM_REPOS.md](../../UPSTREAM_REPOS.md)
