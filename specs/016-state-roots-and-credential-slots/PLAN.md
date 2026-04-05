---
status: draft
last_updated: 2026-04-04
---

# 016 Plan

## Implementation slices

1. Redefine Firebreak's state-mode contract so `host`, `workspace`, `vm`, and `fresh` select runtime state roots while native project config continues to come from the mounted workspace.
2. Remove Firebreak-managed project-config overlays for shipped tools and update wrappers to stop treating project folders such as `.codex/` or `.claude/` as Firebreak-owned state roots.
3. Introduce an opt-in credential-adapter declaration model with shared primitives for file materialization, env-var injection, and helper-command generation.
4. Introduce named credential slots with one default slot plus per-tool overrides inside the same guest.
5. Implement at least one native-login path that writes directly into a selected slot through slot-first materialization.
6. Implement at least one env-driven credential path and one helper-driven credential path through the shared adapter contract.
7. Update docs, diagnostics, and validation to distinguish native project config, runtime state roots, and credential slots clearly.

## Validation approach

- run focused state-root resolution tests for `host`, `workspace`, `vm`, and `fresh`
- run focused tests that prove native project config folders from the mounted workspace are not overwritten by Firebreak
- run focused credential-slot tests for file, env, and helper adapters
- run at least one direct login-to-slot smoke for a file-based login flow
- run at least one multi-tool smoke where a default credential slot and a per-tool override are both active
- run relevant existing package smokes for Codex, Claude Code, and external orchestrator recipes that depend on shared tool wrappers

## Dependencies

- runtime path resolution in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- guest state resolution in [modules/base/guest/resolve-state-root.sh](../../modules/base/guest/resolve-state-root.sh)
- shared wrapper behavior in [modules/base/guest/shared-tool-wrapper.sh](../../modules/base/guest/shared-tool-wrapper.sh)
- shipped package declarations in [nix/outputs/local-vm-artifacts.nix](../../nix/outputs/local-vm-artifacts.nix)
- shared package helpers in [nix/support/runtime.nix](../../nix/support/runtime.nix)

## Current status

Specified only. Implementation has not started.

## Open questions

- which initial tools should define the first credential adapters beyond Codex and Claude Code
- whether slot naming should stay purely free-form or whether Firebreak should later add optional slot metadata
- how much first-slice support should be attempted for platforms whose tools use OS credential stores instead of ordinary files
