---
status: completed
last_updated: 2026-03-21
---

# 005 Isolated Work Tasks Status

## Current phase

Completed.

## What has landed

- `firebreak internal task` supports `create`, `show`, `validate`, and `close`
- each task gets an isolated worktree, runtime root, VM-state root, artifact root, and metadata root
- task creation overlays the current primary-checkout changes into the new worktree so in-progress implementation can be validated there
- task validation runs against the task worktree rather than the repository primary checkout
- task validation preserves machine-readable evidence and latest-validation pointers inside the task artifact root
- the internal task smoke verifies duplicate create handling, resume behavior, parallel validation, and cleanup/disposition flows
- local runner runtime paths were shortened to keep task validation compatible with Unix socket limits

## What remains open

- richer review metadata and reviewer annotations are deferred to later loop work
- cross-host task coordination remains out of scope for this changeset

## Current sources of truth

- [spec](./SPEC.md)
- [plan](./PLAN.md)
- [acceptance](./acceptance/001-work-task-lifecycle.feature)

## History

- 2026-03-20: Spec created to define parallel-safe work tasks for autonomous Firebreak agents and sub-agents.
- 2026-03-21: Implemented the task harness, parallel-safe validation flow, and cleanup/disposition handling.
