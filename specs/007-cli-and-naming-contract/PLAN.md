---
status: active
last_updated: 2026-03-23
---

# 007 Plan

## Implementation slices

1. Define the CLI and naming contract in this spec and acceptance file.
2. Rename internal command packages and routes from `session` / `validate` / `autonomy` to `task` / `validate run` / `loop run`.
3. Rename internal package outputs, smoke packages, and check names to the `firebreak-internal-*` and `firebreak-test-smoke-*` grammar.
4. Update validation suite names, smoke harnesses, and internal tests to the new grammar.
5. Update docs, workflow references, and agent-facing guidance to the new interface.

## Validation approach

- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-claude-code`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-cloud-job`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-internal-validate`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-internal-task`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-internal-loop`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check`

## Dependencies

- current `flake.nix` package wiring
- internal shell applications under `modules/base/host`
- smoke scripts under `modules/base/tests` and `modules/profiles/cloud/tests`

## Current status

- spec drafted
- implementation not started

## Open questions

- none; command moves and naming grammar are already approved for this changeset
