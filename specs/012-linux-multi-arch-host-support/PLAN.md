---
status: draft
last_updated: 2026-03-24
---

# 012 Plan

## Implementation slices

1. Define the Linux multi-arch host contract in this spec.
2. Refactor flake assembly so host systems and guest systems are modeled separately where needed.
3. Expand package and check exports to include `aarch64-linux` alongside `x86_64-linux`.
4. Replace x86-only runner compatibility patching with host-aware logic that remains valid on both supported Linux architectures.
5. Update launcher, diagnostics, validation, and smoke coverage to reflect the supported Linux host matrix.
6. Update repository docs and setup guidance for ARM Linux validation and CI expectations.

## Validation approach

- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check` on `x86_64-linux`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake check` on `aarch64-linux`
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-codex-version` on both supported Linux host architectures
- run `nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run .#firebreak-test-smoke-npx-launcher` on both supported Linux host architectures
- manually verify `nix run .#firebreak-codex` on an `aarch64-linux` host with usable KVM access

## Dependencies

- flake assembly in [flake.nix](../../flake.nix)
- shared flake helper builders in [nix/flake-support.nix](../../nix/flake-support.nix)
- package wiring in [nix/outputs/packages.nix](../../nix/outputs/packages.nix)
- check wiring in [nix/outputs/checks.nix](../../nix/outputs/checks.nix)
- launcher preflight behavior in [bin/firebreak.js](../../bin/firebreak.js)
- runtime and validation scripts under [modules/base/](../../modules/base/)

## Current status

Specified only. Implementation has not started.

## Open questions

- whether runner compatibility logic should remain patch-based or move to explicit Firebreak-controlled QEMU argument generation
- what minimum ARM Linux CI coverage is required before `aarch64-linux` is documented as fully supported
- whether cloud-profile and internal loop surfaces should be validated on `aarch64-linux` in the first landing or in a follow-up
