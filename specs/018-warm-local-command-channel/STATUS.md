---
status: draft
last_updated: 2026-04-05
---

# 018 Warm Local Command Channel Status

## Current phase

Executing the warm local command-channel slices.

## What is landed

- the problem is now explicitly scoped as "separate VM lifetime from command lifetime" rather than "add snapshots first"
- non-interactive local command requests now use an explicit `request.json` contract in the shared exec-output directory
- guest command state now records the request id so host-side dispatch can match responses to requests
- local Linux guests now support an internal `agent-service` mode with a long-lived command agent ready for repeated `agent-exec` requests
- local Linux `agent-exec` requests now route through a backend-private warm instance controller rooted in the stable instance directory

## What remains open

- validation and hardening of the new warm controller path under real VM smoke
- attached warm command dispatch; `agent-attach-exec` still follows the older one-shot path
- snapshot prepare/restore against a ready command-agent state

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)
- [STATUS.md](./STATUS.md)
- [specs/017-runtime-v2/STATUS.md](../017-runtime-v2/STATUS.md)
