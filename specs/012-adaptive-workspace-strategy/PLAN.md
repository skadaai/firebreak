---
status: completed
last_updated: 2026-03-23
---

# 012 Plan

## Implementation slices

1. Define the adaptive workspace contract in this spec.
2. Relax the project skills so tasks do not imply mandatory fresh worktrees.
3. Update supporting docs to distinguish task accountability from workspace isolation.

## Validation approach

- review the updated skills and docs for consistent workspace guidance
- run `git diff --check`

## Dependencies

- current project skills under [`.agents/`](../../.agents)
- current architecture wording in [ARCHITECTURE.md](../../ARCHITECTURE.md)

## Current status

Implemented and reviewed.

## Open questions

- whether a future runtime helper should make workspace strategy machine-selectable as well as documented
