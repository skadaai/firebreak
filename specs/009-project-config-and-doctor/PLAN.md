---
status: completed
last_updated: 2026-03-25
---

# 009 Plan

## Implementation slices

1. Define the public project config contract, precedence rules, and stable key allowlist.
2. Implement `.firebreak.env` discovery and loading for the human-facing Firebreak surface.
3. Remove public compatibility aliases for local mode selection so `FIREBREAK_LAUNCH_MODE` is the only documented selector.
4. Tighten local wrapper state resolution so tool-specific selectors override generic selectors for their matching workloads.
5. Implement `firebreak init` with a minimal Firebreak-native template.
6. Implement `firebreak doctor` with summary, verbose, and JSON output modes.
7. Add acceptance coverage for config loading, precedence, agent-specific overrides, and diagnostics output.
8. Update docs and examples to describe the new config and diagnostics contract.

## Validation approach

- run acceptance coverage for `firebreak init` template generation
- run acceptance coverage for project-config loading and env-overrides-file precedence
- run acceptance coverage for tool-specific selector precedence
- run acceptance coverage for `firebreak doctor` summary and JSON output
- run existing local smoke coverage for Codex and Claude Code packages
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- local wrapper resolution in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- top-level CLI assembly in [modules/base/host/firebreak.sh](../../modules/base/host/firebreak.sh)
- current local smoke harness in [modules/base/tests/agent-smoke.sh](../../modules/base/tests/agent-smoke.sh)
- current CLI and naming contract in [spec 007](../007-cli-and-naming-contract/SPEC.md)
- current single-package local mode contract in [spec 008](../008-single-agent-package-mode/SPEC.md)

## Current status

Implemented. The local workload contract now converges on one shared host state root plus stable per-tool subdirectories, and this workspace still needs path-based validation because the checkout's git metadata remains broken.

## Open questions

- whether `firebreak doctor` should always report all shipped workloads or add an optional agent filter in its first landing
- whether ignored unsupported config keys should produce immediate warnings during load or be surfaced only through `doctor`
