---
status: in_progress
last_updated: 2026-04-01
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
16. Persist attached worker bridge traces and separate post-bootstrap command-output markers so reviewable diagnostics survive request cleanup.
17. Record the strategic pivot explicitly: keep the host-brokered sibling-worker architecture, but stop treating boot-time dynamic package installation as the default attached-worker startup contract.
18. Add a host-owned prepared-tools path for packaged Bun workers so attached worker VMs can reuse prepared toolchains across boots.
19. Add focused validation that launches the same attached packaged worker more than once against shared state and asserts a cache hit or equivalent reuse signal on later runs.
20. Expand guest command probes so attached worker debugging shows the actual live packaged child process, its tty contract, and blocking indicators without requiring manual VM archaeology.
21. Reposition AO end-to-end validation as the final gate after direct packaged-worker readiness and reuse smokes pass.
22. Replace the unstable `script`-piped attached relay with a direct PTY driver and prove the change with a focused interactive sibling-worker smoke.
23. Add guest session-preparation breadcrumbs so long-lived setup steps can be reviewed through preserved runtime artifacts instead of only truncated console output.
24. Extend the prepared-tools contract to packaged node-cli recipes and move their focused smokes onto a no-forward test variant when port ownership is not under test.
25. Capture the operational troubleshooting playbook for VM-spawned processes, including known failure modes, debugging order, and anti-patterns, so future incidents can start from a stable procedure.
26. Collapse the current recipe-authoring split between `workerKinds` and installed worker-proxy scripts into a higher-level `workerProxies` declaration that can derive both from one source of truth for common cases.

## Near-term phased plan

### Phase A: Stabilize packaged-tool delivery

1. Keep the direct PTY relay and the isolated interactive smoke green while packaged-tool work continues.
2. Make the shared-tools or baked-tools path deterministic for Bun-agent workers.
3. Extend the same deterministic shared-tools contract to packaged node-cli workers used by external recipes.
4. Remove or isolate any remaining boot-time step that can turn a successful install into a late bootstrap failure.
5. Keep bootstrap state, ready-marker path, and reuse path visible through machine-readable state and host debug output.

### Phase B: Prove reuse locally

1. Run focused attached-worker smokes twice against the same Firebreak state root.
2. Assert that the second run hits an explicit reuse signal such as `toolchain-cache-hit`.
3. Preserve the runtime evidence for both runs automatically on failure.
4. Replace opportunistic seeding from the default state root with an explicit prewarm or baked-tools contract once the prepared-tools path is stable enough to standardize.

### Phase C: Tighten live command diagnosis

1. Keep surfacing the actual guest command string.
2. Surface the live packaged child process state, including tty contract and blocking hints.
3. Keep explicit session-preparation breadcrumbs for workspace, shared-tools, and exec-output mounts.
4. Only add more attach transport instrumentation if the direct packaged-worker probes stop explaining failures.

### Phase D: Revalidate AO end-to-end

1. Re-run the plain attached `codex` proxy path from the AO VM only after Phases A through C are green.
2. Keep recipe-owned smokes on a no-forward test variant unless the validation target is specifically host port exposure.
3. Treat AO as an integration gate, not as the main debugger for packaged startup.
4. Document the final startup contract and validation flow once the AO path is stable.

### Phase E: Simplify recipe authoring UX

1. Design a high-level `workerProxies` recipe field for the common case where a packaged CLI wants selected command names to launch sibling Firebreak workers.
2. Make that field derive both the guest-visible worker-kind registry and the installed proxy commands automatically.
3. Preserve the lower-level `workerKinds` and explicit proxy-script hooks for advanced or unusual recipes.
4. Migrate the current external recipes once the higher-level path is stable enough to replace duplicated wiring.

## Current execution order

1. Keep `codex` green in both AO and `vibe-kanban` and treat those smokes as regression gates for any shared worker change.
2. Keep `claude` green in AO and `vibe-kanban` while continuing to harden the shared attached-worker lifecycle beneath them.
3. Use the direct shared-layer `claude` exit smoke as the stricter follow-up gate for the remaining lifecycle edge cases, without letting it regress the already-working product paths.
4. Mature or drop any remaining experimental AO/VK harness logic so only durable regression coverage remains in tree.
5. Keep the new `workerProxies` abstraction isolated from future shared TUI lifecycle experiments so the recipe-authoring UX improvement stays banked while lower-level terminal work continues.
6. Defer the shared worker-engine extraction in `modules/profiles/local/module.nix` until after this PR merges, so the merge branch stays focused on behavior and validation rather than wrapper refactors.

## Validation approach

- run focused smoke coverage for host-broker lifecycle operations
- run focused smoke coverage for guest bridge requests and machine-readable worker status
- run focused smoke coverage for `process` versus `firebreak` backend selection
- run focused smoke coverage for attached `firebreak` worker execution without the external orchestrator layer
- run direct packaged-cli readiness smokes that assert guest lifecycle state files instead of only human-visible console output
- run repeated attached packaged-worker smokes against shared state roots to prove cache reuse instead of paying a full install on every boot
- run manual validation against an external orchestrator recipe such as [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- worker state isolation from [spec 005](../005-isolated-work-tasks/SPEC.md)
- local worker package contract from [spec 008](../008-single-agent-package-mode/SPEC.md)
- config-resolution contract from [spec 009](../009-project-config-and-doctor/SPEC.md)
- current local runtime wrapper in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- external project recipe helpers in [nix/support/projects.nix](../../nix/support/projects.nix)

## Current status

Reopened for shared interactive lifecycle hardening. Detached flows, guest-local `process` flows, worker-kind declarations, bounded concurrency, packaged node-cli bootstrap readiness, the worker-proxy helper, the first recipe-owned detached worker lifecycle validation path, the first machine-readable guest lifecycle diagnostics, the direct PTY relay, the isolated interactive sibling-worker smoke, and the first shared-tools/no-forward validation path for packaged node-cli recipes have landed. `codex` is now a protected working path in both AO and `vibe-kanban`, and `claude` is now working in the product-layer AO and `vibe-kanban` VMs as well. The current open slice is stricter shared-layer lifecycle coverage and polish, not generic attach transport or recipe-specific worker spawn.

## Open questions

- whether the guest-visible bridge should remain file-share based or converge on a mounted Unix-socket protocol after the first landing
- whether the first `firebreak` worker backend should always create fresh workers or permit bounded worker reuse
- how much worker log streaming belongs in the first landing versus a follow-up
- whether attached worker logging should remain PTY-only in the first landing or grow a separate PTY recording path in a follow-up
- whether the guest lifecycle contract should remain file-based under the exec-output mount or later converge on a mounted service endpoint
- whether the fastest acceptable packaged-tool delivery path is a host-shared prepared-tools mount, a baked image payload, or a hybrid repair path that uses the shared mount only when the baked payload is absent or stale
- how much of the current transcript-noise cleanup should stay in debug-only views versus becoming part of future optional presentation filtering for live sessions
- when to introduce the higher-level `workerProxies` authoring abstraction relative to the remaining TUI product bugs, since the UX direction is clear but the current priority remains interactive correctness
- how to generalize package-derived local upstream resolution beyond the currently built-in Firebreak-managed worker packages without sliding back into duplicated per-recipe upstream metadata
