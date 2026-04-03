---
status: completed
last_updated: 2026-04-02
---

# 005 Isolated Workspaces Status

## Current phase

Completed.

## What has landed

- `dev-flow workspace` supports `create`, `show`, `validate`, and `close`
- each workspace gets an isolated worktree, runtime root, VM-state root, artifact root, and metadata root
- workspace creation overlays the current primary-checkout changes into the new worktree so in-progress implementation can be validated there
- workspace validation runs against the workspace checkout rather than the repository primary checkout
- workspace validation preserves machine-readable evidence and latest-validation pointers inside the workspace artifact root
- the workspace smoke verifies duplicate create handling, resume behavior, parallel validation, sequential reuse, and cleanup/disposition flows
- local runner runtime paths were shortened to keep workspace validation compatible with Unix socket limits

## What remains open

- richer review metadata and reviewer annotations are deferred to later loop work
- cross-host workspace coordination remains out of scope for this changeset

## Current sources of truth

- [spec](./SPEC.md)
- [plan](./PLAN.md)
- [acceptance](./acceptance/001-work-task-lifecycle.feature)

## History

- 2026-03-20: Spec created to define parallel-safe isolated workspaces for autonomous Firebreak agents and sub-agents.
- 2026-03-21: Implemented the workspace harness, parallel-safe validation flow, and cleanup/disposition handling.
- 2026-04-02: Clarified that attempts and workspaces are separate concepts, and that a new spec line should start a new workspace while sequential work on the same spec reuses the existing one.
