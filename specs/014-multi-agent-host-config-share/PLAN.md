---
status: in_progress
last_updated: 2026-03-25
---

# 014 Plan

## Implementation slices

1. Define the durable multi-agent host config root contract and the stable per-agent subdirectory naming or override rules.
2. Land the shared runtime shape: one `agentVm.multiAgentConfig` subtree, one guest env file, and one shared wrapper implementation.
3. Add guest-visible wrapper commands for shipped agents such as Codex and Claude Code that resolve Firebreak selectors and export agent-native config env vars.
4. Consume the shared contract from a packaged external recipe without recipe-local mount hacks.
5. Add acceptance coverage for generic-vs-agent-specific precedence, per-agent host subdirectory resolution, and wrapper env export behavior.
6. Update docs and external recipe examples to describe the multi-agent host config share model.

## Validation approach

- run acceptance coverage for Codex wrapper resolution in `workspace`, `vm`, `fresh`, and `host` modes
- run acceptance coverage for Claude Code wrapper resolution in `workspace`, `vm`, `fresh`, and `host` modes
- run smoke coverage for one external multi-agent sandbox recipe that installs both agent CLIs
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- current project config contract in [spec 009](../009-project-config-and-doctor/SPEC.md)
- packaged Node CLI sandbox layer in [modules/node-cli/module.nix](../../modules/node-cli/module.nix)
- local wrapper resolution in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- external recipe shape in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)

## Current status

In progress. The first implementation slice now uses a smaller shared contract: one `agentVm.multiAgentConfig` subtree, one host-backed root transport in the local profile, one guest env file for selector defaults, and one shared wrapper implementation in the base runtime. Broader validation coverage and documentation still remain open.

## Open questions

- what the stable per-agent subdirectory names should be for shipped agents and future external recipes
- whether Firebreak should generate wrappers only for shipped agent CLIs or provide a generic wrapper family for external recipes
- whether per-agent host-path overrides belong in a later extension or should stay out of the public contract entirely
