---
status: completed
last_updated: 2026-03-23
---

# 008 Plan

## Implementation slices

1. Define the single-package local-launch contract in this spec and acceptance file.
2. Remove separate public `*-shell` package outputs from `flake.nix`.
3. Keep shell mode available through `FIREBREAK_LAUNCH_MODE=shell` on the public package.
4. Update the local smoke harness to validate both default agent mode and shell override mode through one package.
5. Remove legacy local mode aliases from the public contract and implementation.
6. Update docs and architecture guidance to describe the single-package model.

## Validation approach

- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex-version`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-claude-code`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-cloud-job`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- current local wrapper in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- local guest launch script in [modules/profiles/local/guest/dev-console-start.sh](../../modules/profiles/local/guest/dev-console-start.sh)
- smoke harness in [modules/base/tests/agent-smoke.sh](../../modules/base/tests/agent-smoke.sh)
- flake package wiring in [flake.nix](../../flake.nix)

## Current status

Implemented.

## Open questions

- none; the public mode vocabulary is `run|shell` through `FIREBREAK_LAUNCH_MODE`
