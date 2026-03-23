---
status: completed
last_updated: 2026-03-21
---

# 005 Isolated Work Sessions

## Problem

Autonomous development requires multiple concurrent work attempts, retries, reviews, and experiments.

Those activities are unsafe if they share one mutable checkout, one branch, or one VM state directory. Firebreak already has isolated VM boundaries, but it does not yet define an isolated host-side work-task contract for agent-driven code changes.

Without that contract, parallel agent work remains fragile, cleanup is ad hoc, and evidence from one attempt can leak into another.

## Affected users, actors, or systems

- autonomous Firebreak coding agents
- parallel agent workers or sub-agents
- maintainers reviewing autonomous changes
- local and remote Firebreak hosts that provide workspaces for agent jobs

## Goals

- define a bounded work-task model for autonomous code changes
- give each task an isolated git worktree, branch, and runtime state root
- allow parallel work without shared VM-state collisions
- preserve enough metadata and artifacts for later review or cleanup

## Non-goals

- distributed coordination across many hosts
- long-term artifact archival policy
- replacing Git itself with a custom state model
- making every task persistent forever

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It introduces a host-side work-task contract above Firebreak's VM runtime. Each task represents one bounded autonomous work attempt and owns:

- a dedicated git worktree
- a dedicated branch or resumable task identifier
- isolated VM instance state roots
- isolated agent config and artifact paths
- lifecycle metadata such as creation time, owner, and cleanup status

The intended landing shape is a task harness that multiple agents can use in parallel without mutating each other's worktrees or runner state.

## Requirements

- The system shall provide a work-task contract for autonomous code-change attempts.
- When a new work task is created, the system shall allocate an isolated git worktree and task metadata root for that task.
- When a new work task is created, the system shall allocate isolated VM state paths so that concurrent tasks do not collide on runner volumes or control sockets.
- When a work task is associated with a branch, the system shall prevent another active task from mutating the same worktree path at the same time.
- When a work task starts, the system shall record stable metadata such as task identifier, owning agent, branch, and creation time.
- When a work task ends, the system shall preserve a reviewable record of artifacts, validation outputs, and final disposition before cleanup occurs.
- If a requested work task identifier already exists, then the system shall reject or resume it deterministically instead of creating ambiguous duplicate state.
- While a work task is active, the system shall allow autonomous validation and review steps to run against that task without relying on the repository's primary checkout.

## Acceptance criteria

- A work-task contract exists with explicit worktree, branch, VM-state, and artifact boundaries.
- Parallel work tasks can run without colliding on VM instance state.
- Session lifecycle behavior is explicit for create, resume-or-reject, and cleanup/archive paths.
- Acceptance scenarios exist for isolated creation, parallel execution, and deterministic duplicate-task handling.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [new-worktree.sh](../../scripts/new-worktree.sh)
- [run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)

### Risks

- weak task isolation would let parallel agents overwrite each other's artifacts or git state
- overengineering the first task model could recreate a scheduler before the basic contract is proven
- cleanup that is too aggressive could destroy evidence needed for autonomous review

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
