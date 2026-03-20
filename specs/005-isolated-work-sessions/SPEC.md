---
status: draft
last_updated: 2026-03-20
---

# 005 Isolated Work Sessions

## Problem

Autonomous development requires multiple concurrent work attempts, retries, reviews, and experiments.

Those activities are unsafe if they share one mutable checkout, one branch, or one VM state directory. Firebreak already has isolated VM boundaries, but it does not yet define an isolated host-side work-session contract for agent-driven code changes.

Without that contract, parallel agent work remains fragile, cleanup is ad hoc, and evidence from one attempt can leak into another.

## Affected users, actors, or systems

- autonomous Firebreak coding agents
- parallel agent workers or sub-agents
- maintainers reviewing autonomous changes
- local and remote Firebreak hosts that provide workspaces for agent jobs

## Goals

- define a bounded work-session model for autonomous code changes
- give each session an isolated git worktree, branch, and runtime state root
- allow parallel work without shared VM-state collisions
- preserve enough metadata and artifacts for later review or cleanup

## Non-goals

- distributed coordination across many hosts
- long-term artifact archival policy
- replacing Git itself with a custom state model
- making every session persistent forever

## Morphology and scope of the changeset

This changeset is behavioral and operational.

It introduces a host-side work-session contract above Firebreak's VM runtime. Each session represents one bounded autonomous work attempt and owns:

- a dedicated git worktree
- a dedicated branch or resumable session identifier
- isolated VM instance state roots
- isolated agent config and artifact paths
- lifecycle metadata such as creation time, owner, and cleanup status

The intended landing shape is a session harness that multiple agents can use in parallel without mutating each other's worktrees or runner state.

## Requirements

- The system shall provide a work-session contract for autonomous code-change attempts.
- When a new work session is created, the system shall allocate an isolated git worktree and session metadata root for that session.
- When a new work session is created, the system shall allocate isolated VM state paths so that concurrent sessions do not collide on runner volumes or control sockets.
- When a work session is associated with a branch, the system shall prevent another active session from mutating the same worktree path at the same time.
- When a work session starts, the system shall record stable metadata such as session identifier, owning agent, branch, and creation time.
- When a work session ends, the system shall preserve a reviewable record of artifacts, validation outputs, and final disposition before cleanup occurs.
- If a requested work session identifier already exists, then the system shall reject or resume it deterministically instead of creating ambiguous duplicate state.
- While a work session is active, the system shall allow autonomous validation and review steps to run against that session without relying on the repository's primary checkout.

## Acceptance criteria

- A work-session contract exists with explicit worktree, branch, VM-state, and artifact boundaries.
- Parallel work sessions can run without colliding on VM instance state.
- Session lifecycle behavior is explicit for create, resume-or-reject, and cleanup/archive paths.
- Acceptance scenarios exist for isolated creation, parallel execution, and deterministic duplicate-session handling.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [spec 004](../004-autonomous-vm-validation/SPEC.md)
- [new-worktree.sh](../../scripts/new-worktree.sh)
- [run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)

### Risks

- weak session isolation would let parallel agents overwrite each other's artifacts or git state
- overengineering the first session model could recreate a scheduler before the basic contract is proven
- cleanup that is too aggressive could destroy evidence needed for autonomous review

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)
