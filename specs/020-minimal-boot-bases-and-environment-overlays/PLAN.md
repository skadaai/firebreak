---
status: draft
last_updated: 2026-04-07
---

# 020 Minimal Boot Bases And Environment Overlays Plan

## Current status

This changeset is at the design-definition stage.

Firebreak already has some groundwork:

- shared host `/nix/store` access
- persistent tool-runtime mounts
- host-driven tool-runtime seeding
- package-specific overlay modules

But the environment model is still too ad hoc, and the boot base is still too generic.

## Implementation slices

### Slice 1: environment contract

- define the Firebreak environment overlay contract
- define what package recipes may declare
- define what project-local Nix declarations may contribute
- define strict boundaries on what the environment layer may not override

### Slice 2: environment identity and cache

- define the environment hash inputs
- add a reusable host-side cache layout for resolved environments
- make reuse explicit and inspectable

### Slice 3: host-side resolver

- resolve package defaults plus project-local Nix declarations on the host
- map the result into a constrained Firebreak environment representation
- fail explicitly on unsupported project-local shapes

### Slice 4: base-class split

- define Firebreak-owned `command` and `interactive` boot bases
- move command and shell paths onto those smaller boot targets
- continue shrinking kernel, initrd, and service graphs against those bases

### Slice 5: guest integration

- expose resolved environment overlays inside the guest
- make command and shell flows wait only for the environment they actually need
- keep the runtime boundaries visible and explicit

## Validation approach

- host-side cache-key tests for environment identity stability
- repeated-launch comparisons for reused versus changed environments
- project-local Nix declaration tests with explicit accept/reject expectations
- cold boot comparisons for `command` and `interactive` bases
- end-to-end package and workspace environment reuse smokes
