---
status: draft
last_updated: 2026-04-05
---

# 018 Warm Local Command Channel Status

## Current phase

Design definition.

## What is landed

- the problem is now explicitly scoped as "separate VM lifetime from command lifetime" rather than "add snapshots first"

## What remains open

- guest command-agent design
- host detached-instance controller
- running-instance command dispatch
- snapshot prepare/restore against a ready command-agent state

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)
- [STATUS.md](./STATUS.md)
- [specs/017-runtime-v2/STATUS.md](../017-runtime-v2/STATUS.md)
