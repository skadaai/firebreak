---
status: completed
last_updated: 2026-03-23
---

# 012 Adaptive Workspace Strategy

## Problem

Firebreak's current autonomous skills and related docs treat a bounded task as if it must always create a fresh branch and worktree.

That is too expensive for normal sequential work:

- it creates unnecessary workspace branches
- it makes the harness feel heavier than the change itself
- it conflates task accountability with workspace isolation

The system already benefits from isolated worktrees for parallel or risky work. The mistake is making that mechanism the default for every slice.

## Affected users, actors, or systems

- coding agents choosing how to start work
- maintainers reviewing autonomous workspace behavior
- the task/worktree harness and the docs that explain it

## Goals

- keep task as the unit of accountability, validation, and review
- default to the simplest safe workspace for a slice
- reserve fresh branches and isolated worktrees for cases where they buy real safety
- reduce gratuitous workspace proliferation in normal sequential work

## Non-goals

- removing the isolated task/worktree harness
- redesigning `firebreak internal task`
- introducing a new workspace taxonomy or extra control-plane machinery

## Morphology and scope of the changeset

This changeset is behavioral and documentation-oriented.

It updates Firebreak's autonomous guidance so that:

- a bounded task does not automatically imply a fresh branch or worktree
- the current safe workspace is reused by default for sequential work
- isolated worktrees are used intentionally for parallel, risky, or branch-sensitive work

## Requirements

- The system shall treat task as the unit of accountability, not as a mandatory fresh worktree.
- When a bounded slice can be completed safely in the current workspace, the system shall prefer reusing that workspace.
- When work is parallel, high-risk, or needs a distinct branch boundary, the system shall prefer an isolated worktree.
- The system shall not teach coding agents that every new slice requires a new branch or worktree.
- The system shall keep the isolated task/worktree harness available as an explicit safety tool.

## Acceptance criteria

- The project skills no longer instruct agents to create a fresh task worktree for every bounded slice.
- The project skills explicitly prefer the simplest safe workspace.
- The project skills explicitly reserve isolated worktrees for parallel, risky, or branch-sensitive work.
- Supporting docs no longer equate task with mandatory fresh worktree creation.

## Dependencies and risks

### Dependencies

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [spec 005](../005-isolated-work-tasks/SPEC.md)
- the project skillset under [`.agents/`](../../.agents)

### Risks

- if the rule is relaxed too far, agents may edit unsafe shared workspaces casually
- if the rule stays too strong, agents will keep creating unnecessary branches and worktrees
- if docs and skills drift apart, the harness will remain confusing

## Relevant constitutional and product docs

- [engineering/SPECS.md](../../engineering/SPECS.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
