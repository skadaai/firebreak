---
status: in_progress
last_updated: 2026-03-27
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
13. Add a machine-readable guest lifecycle contract for packaged-cli bootstrap and command handoff, and surface it through `firebreak worker debug`.
14. Add direct readiness smokes that assert guest lifecycle artifacts and preserve runtime evidence automatically on failure.
15. Record the lifecycle-state contract and validation flow in the spec so future runtime and test changes cannot drift silently.

## Validation approach

- run focused smoke coverage for host-broker lifecycle operations
- run focused smoke coverage for guest bridge requests and machine-readable worker status
- run focused smoke coverage for `process` versus `firebreak` backend selection
- run focused smoke coverage for attached `firebreak` worker execution without the external orchestrator layer
- run direct packaged-cli readiness smokes that assert guest lifecycle state files instead of only human-visible console output
- run manual validation against an external orchestrator recipe such as [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- worker state isolation from [spec 005](../005-isolated-work-tasks/SPEC.md)
- local worker package contract from [spec 008](../008-single-agent-package-mode/SPEC.md)
- config-resolution contract from [spec 009](../009-project-config-and-doctor/SPEC.md)
- current local runtime wrapper in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- external project recipe helpers in [nix/support/projects.nix](../../nix/support/projects.nix)

## Current status

Reopened for attached `firebreak` worker hardening. Detached flows, guest-local `process` flows, worker-kind declarations, bounded concurrency, packaged node-cli bootstrap readiness, the worker-proxy helper, the first recipe-owned detached worker lifecycle validation path, and the first machine-readable guest lifecycle diagnostics have landed. The current open slice is the remaining nested `codex` startup behavior inside the attached sibling-worker path.

## Open questions

- whether the guest-visible bridge should remain file-share based or converge on a mounted Unix-socket protocol after the first landing
- whether the first `firebreak` worker backend should always create fresh workers or permit bounded worker reuse
- how much worker log streaming belongs in the first landing versus a follow-up
- whether attached worker logging should remain PTY-only in the first landing or grow a separate PTY recording path in a follow-up
- whether the guest lifecycle contract should remain file-based under the exec-output mount or later converge on a mounted service endpoint
