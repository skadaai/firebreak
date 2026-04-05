---
status: in_progress
last_updated: 2026-03-25
---

# 014 Plan

## Implementation slices

1. Define the durable shared host state-root contract and the stable per-tool subdirectory naming rules across dedicated and shared-sandbox workloads.
2. Land the shared runtime shape: one `workloadVm.sharedStateRoots` subtree, one guest env file, and one shared wrapper implementation.
3. Migrate dedicated Codex and Claude Code local packages to the same host-root-plus-subdirectory contract.
4. Add guest-visible wrapper commands for shipped tools such as Codex and Claude Code that resolve Firebreak selectors and export tool-native config env vars.
5. Consume the shared contract from a packaged external recipe without recipe-local mount hacks.
6. Add acceptance coverage for generic-vs-tool-specific precedence, per-tool host subdirectory resolution, wrapper env export behavior, and project-local workspace isolation.
7. Update docs and external recipe examples to describe the shared host-root model.

## Validation approach

- run acceptance coverage for Codex wrapper resolution in `workspace`, `vm`, `fresh`, and `host` modes
- run acceptance coverage for Claude Code wrapper resolution in `workspace`, `vm`, `fresh`, and `host` modes
- run smoke coverage for one external shared-sandbox recipe that installs both tool CLIs
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- current project config contract in [spec 009](../009-project-config-and-doctor/SPEC.md)
- packaged Node CLI sandbox layer in [modules/node-cli/module.nix](../../modules/node-cli/module.nix)
- local wrapper resolution in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- external recipe shape in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)

## Current status

In progress. The shared host-root contract now covers the external shared sandbox and the dedicated Codex and Claude Code local packages. Broader validation coverage and documentation still remain open.

## Open questions

- what the stable per-tool subdirectory names should be for future shipped tools and external recipes beyond Codex and Claude Code
- whether Firebreak should generate wrappers only for shipped tool CLIs or provide a generic wrapper family for external recipes
- whether per-tool host-path overrides belong in a later extension or should stay out of the public contract entirely
