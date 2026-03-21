---
status: completed
last_updated: 2026-03-21
---

# 005 Isolated Work Sessions Status

## Current phase

Completed.

## What has landed

- `firebreak session` supports `create`, `show`, `validate`, and `close`
- each session gets an isolated worktree, runtime root, VM-state root, artifact root, and metadata root
- session creation overlays the current primary-checkout changes into the new worktree so in-progress implementation can be validated there
- session validation runs against the session worktree rather than the repository primary checkout
- session validation preserves machine-readable evidence and latest-validation pointers inside the session artifact root
- the session smoke verifies duplicate create handling, resume behavior, parallel validation, and cleanup/disposition flows
- local runner runtime paths were shortened to keep session validation compatible with Unix socket limits

## What remains open

- richer review metadata and reviewer annotations are deferred to later autonomy work
- cross-host session coordination remains out of scope for this changeset

## Current sources of truth

- [spec](./SPEC.md)
- [plan](./PLAN.md)
- [acceptance](./acceptance/001-work-session-lifecycle.feature)

## History

- 2026-03-20: Spec created to define parallel-safe work sessions for autonomous Firebreak agents and sub-agents.
- 2026-03-21: Implemented the session harness, parallel-safe validation flow, and cleanup/disposition handling.
