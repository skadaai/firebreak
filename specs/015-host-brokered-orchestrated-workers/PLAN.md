---
status: in_progress
last_updated: 2026-03-26
---

# 015 Plan

## Implementation slices

1. Define the host-brokered orchestration contract, control-plane nouns, and backend vocabulary in this spec.
2. Add a host-side broker surface that can create, list, inspect, and stop orchestrated workers.
3. Add a guest-side bridge surface so orchestrator sandboxes can request workers without touching raw host runner internals.
4. Introduce worker-kind declarations for external recipes with backend selection and bounded concurrency.
5. Implement the `firebreak` worker backend by launching sibling Firebreak workers with host-owned state roots.
6. Implement the `process` worker backend as the baseline shared-guest execution path.
7. Integrate the first external orchestrator recipe against the new control surface.
8. Add focused validation for the first external orchestrator recipe, including worker-wrapper installation, bootstrap readiness, and worker creation semantics.
9. Add smoke and manual validation for worker lifecycle, backend selection, workspace semantics, and cleanup.
10. Isolate attached `firebreak` worker execution with a minimal smoke that does not depend on the external orchestrator recipe.
11. Add focused attach diagnostics so request publication, bridge execution, worker launch, and worker completion are reviewable when attached sibling-worker runs fail.
12. Re-validate the external `codex` proxy path only after the minimal attached `firebreak` worker path is proven.

## Validation approach

- run focused smoke coverage for host-broker lifecycle operations
- run focused smoke coverage for guest bridge requests and machine-readable worker status
- run focused smoke coverage for `process` versus `firebreak` backend selection
- run focused smoke coverage for attached `firebreak` worker execution without the external orchestrator layer
- run manual validation against an external orchestrator recipe such as [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- worker state isolation from [spec 005](../005-isolated-work-tasks/SPEC.md)
- local worker package contract from [spec 008](../008-single-agent-package-mode/SPEC.md)
- config-resolution contract from [spec 009](../009-project-config-and-doctor/SPEC.md)
- current local runtime wrapper in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- external project recipe helpers in [nix/support/projects.nix](../../nix/support/projects.nix)

## Current status

Reopened for attached `firebreak` worker hardening. Detached flows, guest-local `process` flows, worker-kind declarations, bounded concurrency, packaged node-cli bootstrap readiness, the worker-proxy helper, and the first recipe-owned detached worker lifecycle validation path have landed. The remaining open slice is focused attached sibling-worker execution for interactive CLIs such as `codex`.

## Open questions

- whether the guest-visible bridge should remain file-share based or converge on a mounted Unix-socket protocol after the first landing
- whether the first `firebreak` worker backend should always create fresh workers or permit bounded worker reuse
- how much worker log streaming belongs in the first landing versus a follow-up
- whether attached worker logging should remain PTY-only in the first landing or grow a separate PTY recording path in a follow-up
