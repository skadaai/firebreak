---
status: draft
last_updated: 2026-03-19
---

# 003 Remote Job Host Status

## Current phase

Draft.

## What has landed

- the single-host remote execution changeset has been scoped
- behavioral acceptance has been defined at the spec level

## What remains open

- implementation of the host-side runner
- implementation of capacity and timeout guardrails
- end-to-end validation of the remote job contract

## Current sources of truth

- [spec](./specs/003-remote-job-host/SPEC.md)
- [plan](./specs/003-remote-job-host/PLAN.md)
- [acceptance](./specs/003-remote-job-host/acceptance/001-remote-job-host.feature)

## History

- 2026-03-19: Spec created to define a bounded first remote execution path after the guest cloud profile is established.
