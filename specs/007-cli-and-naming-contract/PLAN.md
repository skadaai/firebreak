---
status: active
last_updated: 2026-04-02
---

# 007 Plan

## Implementation slices

1. Define the CLI and naming contract in this spec and acceptance file.
2. Move development workflow commands out of `firebreak` and into the dedicated `dev-flow` CLI.
3. Rename the host-side isolated checkout concept from `task` to `workspace`, while keeping `attempt` as the bounded loop unit.
4. Rename workflow packages, smoke packages, and checks to the `dev-flow-*` and `*-test-smoke-*` grammar where appropriate.
5. Update validation suite names, smoke harnesses, and launcher paths to the new interface.
6. Update docs, workflow references, and agent-facing guidance to the new interface.

## Validation approach

- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-claude-code`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-cloud-job`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#dev-flow-test-smoke-validate`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#dev-flow-test-smoke-workspace`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#dev-flow-test-smoke-loop`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- current `flake.nix` package wiring
- shell applications under `modules/base/host`
- smoke scripts under `modules/base/tests` and `modules/profiles/cloud/tests`

## Current status

- spec revised for the separate `dev-flow` CLI and workspace/attempt split
- implementation in progress

## Open questions

- none; command moves and naming grammar are already approved for this changeset
