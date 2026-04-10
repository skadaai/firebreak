---
status: in_progress
last_updated: 2026-03-24
---

# 012 Status

## Current phase

Implemented in code and validated through flake evaluation plus launcher smoke coverage. Real `aarch64-linux` runtime validation remains open.

## What has landed

- a tracked spec, plan, and status record for expanding Firebreak local host support from `x86_64-linux` to include `aarch64-linux`
- flake output assembly now exports `packages`, `checks`, and `lib` for both `x86_64-linux` and `aarch64-linux`
- package and check wiring now derive per-system VM artifacts without depending on one global `nixosConfigurations` host system
- runner compatibility patching now avoids x86-only CPU replacement on non-`x86_64-linux` hosts
- launcher preflight now accepts Linux `x64` and `arm64`
- launcher smoke coverage now asserts both unsupported-arch rejection and Linux `arm64` acceptance through the test hooks
- repository docs and the self-hosted VM smoke workflow now reflect the widened Linux host contract

## What remains open

- confirm runtime behavior on real `aarch64-linux` hardware with usable KVM access
- decide whether to add dedicated `aarch64-linux` self-hosted smoke capacity instead of the now architecture-agnostic `linux` + `kvm` runner label match

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec in response to the conclusion that Linux multi-arch host support is substantial enough to require its own tracked changeset before implementation.
- 2026-03-24: Began implementation by refactoring flake output assembly toward per-system VM artifacts and widening the documented Linux host contract to include `aarch64-linux`.
- 2026-03-24: Validated that `packages.x86_64-linux.firebreak`, `packages.aarch64-linux.firebreak`, `checks.aarch64-linux.firebreak-codex-system`, and the NPX launcher smoke all evaluate or pass in the workspace checkout.
