---
status: completed
last_updated: 2026-04-02
---

# 005 Isolated Workspaces

## Problem

Autonomous development requires multiple concurrent spec lines, retries, reviews, and experiments.

Those activities are unsafe if they share one mutable checkout, one branch, or one VM state directory. Firebreak already has isolated VM boundaries, but it also needs a host-side workspace contract for agent-driven code changes.

The earlier task model blurred together two different concepts: the bounded attempt and the isolated checkout. Without a clear separation, agents over-create worktrees for every slice instead of using isolation to separate genuinely different spec lines.

## Affected users, actors, or systems

- autonomous Firebreak coding agents
- parallel agent workers or sub-agents
- maintainers reviewing autonomous changes
- local and remote Firebreak hosts that provide workspaces for agent jobs

## Goals

- define a bounded workspace model for autonomous code changes
- give each workspace an isolated git worktree, branch, and runtime state root
- allow parallel work without shared VM-state collisions
- preserve enough metadata and artifacts for later review or cleanup

## Non-goals

- distributed coordination across many hosts
- long-term artifact archival policy
- replacing Git itself with a custom state model
- making every task persistent forever

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It introduces a host-side workspace contract above Firebreak's VM runtime. A workspace represents one spec line or other logically related sequence of work and owns:

- a dedicated git worktree
- a dedicated branch or resumable workspace identifier
- isolated VM instance state roots
- isolated agent config and artifact paths
- lifecycle metadata such as creation time, owner, and cleanup status

Attempts remain separate from workspaces. Multiple bounded attempts may happen sequentially in one workspace when they belong to the same spec line. A new spec or unrelated maintenance line must use a different workspace.

The intended landing shape is a workspace harness that multiple agents can use in parallel without mutating each other's worktrees or runner state.

## Requirements

- The system shall provide a workspace contract for autonomous code-change attempts.
- When a new workspace is created, the system shall allocate an isolated git worktree and workspace metadata root for that workspace.
- When a new workspace is created, the system shall allocate isolated VM state paths so that concurrent workspaces do not collide on runner volumes or control sockets.
- When a workspace is associated with a branch, the system shall prevent another active workspace from mutating the same worktree path at the same time.
- When a workspace starts, the system shall record stable metadata such as workspace identifier, owning agent, branch, spec line, and creation time.
- When a workspace ends, the system shall preserve a reviewable record of artifacts, validation outputs, and final disposition before cleanup occurs.
- If a requested workspace identifier already exists, then the system shall reject or resume it deterministically instead of creating ambiguous duplicate state.
- While a workspace is active, the system shall allow autonomous validation and review steps to run against that workspace without relying on the repository's primary checkout.
- When an agent continues sequential work on the same spec line, the system shall prefer reusing the current workspace instead of creating a new one for every slice.
- When an agent starts work on a different spec or unrelated maintenance line, the system shall require a separate workspace instead of sharing the existing one.

## Acceptance criteria

- A workspace contract exists with explicit worktree, branch, VM-state, and artifact boundaries.
- Parallel workspaces can run without colliding on VM instance state.
- Workspace lifecycle behavior is explicit for create, reuse, resume-or-reject, and cleanup/archive paths.
- Acceptance scenarios exist for isolated creation, parallel execution, sequential reuse on one spec, and deterministic duplicate-workspace handling.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [new-worktree.sh](../../scripts/new-worktree.sh)
- [run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)

### Risks

- weak workspace isolation would let parallel agents overwrite each other's artifacts or git state
- overengineering the first workspace model could recreate a scheduler before the basic contract is proven
- cleanup that is too aggressive could destroy evidence needed for autonomous review

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
