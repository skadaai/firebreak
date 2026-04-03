---
status: in_progress
last_updated: 2026-03-24
---

# 013 Plan

## Implementation slices

1. Define the Apple Silicon local-support contract in this spec.
2. Add `aarch64-darwin` host-side flake exports while keeping Linux and Darwin host/guest concerns explicit.
3. Introduce a host-specific local runtime split:
   - Linux local path remains QEMU-first.
   - Apple Silicon local path uses `vfkit`.
4. Refactor local sharing and host-metadata plumbing so the Apple Silicon path uses `vfkit`-compatible semantics.
5. Update launcher and diagnostics to:
   - recognize Apple Silicon local support
   - reject Intel Macs clearly
   - stop treating Linux `/dev/kvm` as the universal local readiness model
6. Land the minimum viable first launch path for Apple Silicon local use:
   - `firebreak-codex` local launch
   - `firebreak-claude-code` local launch
   - shell mode
   - workspace share
   - agent config share
   - one-shot `--version`-style command execution
7. Add Apple Silicon-specific smoke coverage where practical and document the required real-hardware validation.

## Minimum viable first launch path

The first acceptable landing shape is:

- `aarch64-darwin` host support only
- `aarch64-linux` guest only
- `vfkit` only
- local profile only
- no cloud support
- no runtime-profile selection UI
- enough share support to preserve workspace access, config access, and one-shot command execution

This MVP is intentionally narrower than full platform parity. It is the first product-credible Apple Silicon local path, not the end state of all future refinement.

## Validation approach

- run `bash ./scripts/run-flake.sh eval .#packages.aarch64-darwin.firebreak-codex.name --raw`
- run `bash ./scripts/run-flake.sh eval .#packages.aarch64-darwin.firebreak-claude-code.name --raw`
- run `bash ./scripts/run-flake.sh eval .#checks.aarch64-darwin.firebreak-codex-system.drvPath --raw`
- run `bash ./scripts/run-flake.sh run .#firebreak-test-smoke-npx-launcher`
- manually validate on a real Apple Silicon Mac:
  - `nix run .#firebreak-codex`
  - `FIREBREAK_LAUNCH_MODE=shell nix run .#firebreak-codex`
  - one-shot `--version` execution
  - workspace sharing
  - agent config sharing

## Dependencies

- flake assembly in [flake.nix](../../flake.nix)
- local runtime support in [nix/support/runtime.nix](../../nix/support/runtime.nix)
- base VM configuration in [modules/base/module.nix](../../modules/base/module.nix)
- local profile behavior in [modules/profiles/local/module.nix](../../modules/profiles/local/module.nix)
- local host wrapper behavior in [modules/profiles/local/host/run-wrapper.sh](../../modules/profiles/local/host/run-wrapper.sh)
- launcher behavior in [bin/firebreak.js](../../bin/firebreak.js)

## Current status

Implemented in the bounded Firebreak task worktree, with flake evaluation and launcher smoke validation completed. Real Apple Silicon runtime validation on hardware remains open.

## Open questions

- whether the `vfkit` share injection path should remain a Firebreak wrapper concern or move into a more explicit local-runtime abstraction later
- whether Linux and Apple Silicon local runtimes should share one wrapper with host-specific hooks or split further into separate host runtime modules
- what minimum Apple Silicon hardware validation is required before this support is documented as fully supported rather than evaluation-complete
