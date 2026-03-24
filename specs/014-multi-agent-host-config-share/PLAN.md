---
status: draft
last_updated: 2026-03-24
---

# 014 Plan

## Implementation slices

1. Define the durable multi-agent host config root contract and the stable per-agent subdirectory naming or override rules.
2. Extend the packaged Node CLI sandbox layer so a recipe can opt into multi-agent host config behavior.
3. Add guest-visible wrapper commands for shipped agents such as Codex and Claude Code that resolve Firebreak selectors and export agent-native config env vars.
4. Decide whether the shared-root contract needs one new public env var for multi-agent host roots or can reuse the existing per-agent host path selectors without ambiguity.
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

Specified only. Implementation has not started.

## Open questions

- whether the shared host root should use a new public env var or reuse the existing host-path selectors with multi-agent-specific interpretation
- what the stable per-agent subdirectory names should be for shipped agents and future external recipes
- whether Firebreak should generate wrappers only for shipped agent CLIs or provide a generic wrapper family for external recipes
