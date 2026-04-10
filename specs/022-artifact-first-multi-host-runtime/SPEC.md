---
status: draft
last_updated: 2026-04-10
---

# 022 Artifact-First Multi-Host Runtime

## Problem

Firebreak currently supports multiple host architectures, but the product model still leans too hard on "build the guest where you launch it".

That causes the wrong kind of complexity in the exact places where Firebreak is supposed to feel simpler than Docker and general-purpose VM tooling:

- Apple Silicon macOS can host Firebreak through `vfkit`, but current end-to-end CI breaks because the Darwin host is asked to build Linux guest closures locally.
- secondary-architecture CI has to reason about builder availability and host-vs-guest platform mismatches instead of just testing whether Firebreak can boot and run a workload.
- users risk paying first-run cost as "host builds a Linux VM" rather than "host fetches and boots a Linux workload artifact".

For Firebreak to become an easier-to-use alternative to Docker and general virtualization, it needs a clearer product split:

- Linux guest artifacts are built on Linux
- host-specific runtimes consume those artifacts
- end users and CI should default to fetch-and-run rather than host-local guest construction

## Goals

- make Linux guest artifacts the canonical runtime artifact Firebreak distributes and reuses
- keep host-specific runtime logic thin and focused on launch, mounts, networking, and UX
- let `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin` consume the same guest-architecture-specific Linux artifacts where semantics match
- make Apple Silicon local runtime validation prove real VM boot behavior instead of only host-entry behavior once artifact consumption exists
- make any temporary CI coverage reductions for missing host or provider capabilities explicitly temporary, with restoration of full supported-runtime coverage required once those capabilities exist
- preserve Firebreak's fail-fast runtime boundaries and explicit platform contracts
- keep local source builds and advanced builder wiring available without making them the default product path

## Non-goals

- making every host build every guest artifact locally
- treating Darwin as a Linux build platform for guest closures by default
- replacing the environment-overlay model from [spec 020](../020-minimal-boot-bases-and-environment-overlays/SPEC.md)
- replacing the public cache layer from [spec 021](../021-public-cache-layer/SPEC.md)
- introducing opaque hosted services as the only way to use Firebreak
- supporting arbitrary guest operating systems in this changeset

## Direction

Firebreak should move to an artifact-first runtime model:

### 1. Canonical guest artifacts

Firebreak should produce canonical Linux guest artifacts per guest architecture and boot base.

Examples:

- `x86_64-linux` guest artifact for the `command` boot base
- `x86_64-linux` guest artifact for the `interactive` boot base
- `aarch64-linux` guest artifact for the `command` boot base
- `aarch64-linux` guest artifact for the `interactive` boot base

These artifacts represent Firebreak-owned guest runtime semantics. They are not package identities and they are not host-specific launchers.

### 2. Thin host runtimes

Each supported host should provide a thin runtime adapter that:

- selects the right guest artifact
- launches it with the host-specific hypervisor/backend
- mounts Firebreak-managed state, environment overlays, and workspace data
- exposes Firebreak UX such as interactive attach, worker bridging, and diagnostics

Examples:

- `x86_64-linux` host runtime: `cloud-hypervisor` / KVM
- `aarch64-linux` host runtime: `cloud-hypervisor` / KVM
- `aarch64-darwin` host runtime: `vfkit`

### 3. Host-resolved additive overlays

Package defaults, project-local Nix inputs, and shared state remain separate host-resolved layers as defined by [spec 020](../020-minimal-boot-bases-and-environment-overlays/SPEC.md).

The guest artifact is the stable runtime substrate.

The environment overlay is additive on top of that substrate.

The state layer remains mutable and external to the guest artifact.

## Product model

Firebreak should present one product idea:

> Launch a Linux workload artifact through a host-specific Firebreak runtime.

That means:

- users on Linux and Apple Silicon macOS should think in terms of the same Firebreak workload identity
- the host runtime may differ, but the guest artifact contract should not drift arbitrarily by host
- the default path should prefer substitution or artifact fetch over local guest construction

This is the closest Firebreak analogue to how container tools work in practice:

- the user consumes Linux workload artifacts
- the host runtime is platform-specific
- the host should not need to assemble the workload from scratch on every machine

## Artifact contract

The artifact-first model should define four explicit identities.

### Guest artifact identity

The guest artifact identity shall include at minimum:

- Firebreak runtime version
- guest architecture
- boot base
- guest runtime contract version

It shall not include package-specific or workspace-specific mutable state.

### Environment overlay identity

The environment overlay identity remains separate and shall include the additive inputs defined by [spec 020](../020-minimal-boot-bases-and-environment-overlays/SPEC.md).

### Host runtime identity

The host runtime identity shall include:

- host system
- selected backend
- host-side wrapper/runtime version

This identity is about launch semantics, not guest filesystem content.

### State identity

The state layer identity remains external and mutable:

- shared state roots
- credential slots
- workspace mounts
- task and worker metadata

## Platform model

Firebreak should distinguish host and guest explicitly.

### Linux hosts

- `x86_64-linux` hosts consume `x86_64-linux` guest artifacts
- `aarch64-linux` hosts consume `aarch64-linux` guest artifacts
- KVM-backed local runtime remains the default end-to-end path

### Apple Silicon macOS hosts

- `aarch64-darwin` hosts consume `aarch64-linux` guest artifacts
- `vfkit` remains the host runtime
- the default product path shall not require the Darwin host to build Linux guest closures locally

### Builder model

Linux guest artifacts should be built on Linux builders.

When a host cannot build the guest artifact natively, the product should prefer:

1. trusted substitution of a published artifact
2. distributed or remote Linux builders
3. local Linux build only when the host is itself a compatible Linux build platform

It should not default to "try to build Linux guest closures on a non-Linux host and hope Nix sorts it out".

## Requirements

- Firebreak shall define canonical Linux guest artifacts as first-class product outputs.
- Firebreak shall keep guest artifact identity separate from host runtime identity.
- Firebreak shall keep guest artifact identity separate from environment overlay identity.
- Firebreak shall keep mutable runtime state outside the guest artifact.
- Firebreak shall let multiple host runtimes consume the same guest-architecture-specific Linux artifact when the guest semantics are equivalent.
- Firebreak shall treat Linux as the canonical build platform for Linux guest artifacts.
- Firebreak shall not require `aarch64-darwin` hosts to build Linux guest closures locally for the default end-user path.
- Firebreak shall support Apple Silicon local runtime consumption of prebuilt Linux guest artifacts through `vfkit`.
- Firebreak shall preserve explicit failure when the required guest artifact cannot be fetched, built, or delegated to a compatible builder.
- Firebreak shall preserve explicit failure when a host runtime cannot satisfy its backend requirements.
- Firebreak shall continue to allow advanced source-build workflows, but those workflows shall not define the default product experience.
- Firebreak shall let CI test host-runtime behavior separately from guest-artifact production where that separation reduces duplicated work without hiding incompatibilities.
- Firebreak shall treat temporary CI reductions caused by missing provider or host capabilities as implementation gaps to be removed once the required capability becomes available.

## CI and validation implications

The artifact-first model changes what CI should prove.

### Guest-artifact production CI

Linux CI should remain the canonical place that proves:

- guest artifacts build correctly
- boot-base changes are valid
- environment overlays integrate correctly with those artifacts

### Host-runtime consumption CI

Per-host CI should prove:

- the host runtime can consume the expected guest artifact
- the workload boots and runs end to end
- host-specific mounts, networking, attach, and diagnostics behave correctly

This means:

- `aarch64-linux` CI should run real KVM-backed Firebreak guest boots
- `aarch64-darwin` CI should eventually run real `vfkit` boots against prebuilt Linux guest artifacts
- Darwin CI should stop pretending to validate guest construction locally once artifact consumption is the intended product path
- if current CI infrastructure cannot yet satisfy one of those host-runtime paths, the reduced coverage must be recorded as temporary and the implementation plan must include restoring the missing end-to-end coverage when the capability is available

## Proposed implementation shape

### 1. Make guest artifacts explicit

- define canonical guest artifact outputs by guest architecture and boot base
- keep them Firebreak-owned and package-independent
- make their identities inspectable from the CLI and diagnostics

### 2. Align launchers with artifact consumption

- update local wrappers to resolve a guest artifact identity first
- fetch or substitute that artifact when available
- fall back to a compatible Linux builder path only when necessary

### 3. Keep package behavior additive

- package modules continue declaring environment overlays, defaults, and launch behavior
- package identity does not become guest-image identity again

### 4. Teach Darwin to consume, not build

- wire `aarch64-darwin` local runtime to consume `aarch64-linux` guest artifacts as its default path
- treat remote/distributed Linux building as an advanced fallback, not the baseline contract

### 5. Split CI around production vs consumption

- Linux CI produces and validates guest artifacts
- host-specific CI validates consumption paths
- scheduled sweeps can still run broader host coverage, but against published or prebuilt guest artifacts where appropriate
- provider or runner capability probes may be used to fail early and diagnose infrastructure regressions, but they shall not redefine the long-term supported-runtime coverage target

## Acceptance criteria

- Firebreak exposes canonical Linux guest artifacts as explicit outputs rather than only implicit per-host derivation trees.
- `x86_64-linux` and `aarch64-linux` can build and run their guest artifacts end to end through their local runtimes.
- `aarch64-darwin` can boot and run a Firebreak workload through `vfkit` using a prebuilt `aarch64-linux` guest artifact without requiring local Darwin guest construction.
- package-specific customization continues to flow through additive environment overlays rather than per-package full guest images.
- CI can separately validate guest-artifact production and host-runtime consumption without losing end-to-end host confidence.
- CI and workflow policy make it explicit that reduced host-runtime coverage caused by missing KVM, missing `vfkit` execution, or similar provider limits is temporary and must be restored once the underlying capability is ready.
- the default product path on a fresh supported host is closer to "fetch and boot" than to "construct a Linux guest from source on this machine".

## Dependencies and risks

### Dependencies

- [spec 012](../012-linux-multi-arch-host-support/SPEC.md)
- [spec 013](../013-apple-silicon-local-support/SPEC.md)
- [spec 017](../017-runtime-v2/SPEC.md)
- [spec 020](../020-minimal-boot-bases-and-environment-overlays/SPEC.md)
- [spec 021](../021-public-cache-layer/SPEC.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)

### Risks

- if guest artifact identity is underspecified, different boot bases or runtime contracts could be mixed incorrectly
- if package behavior leaks back into guest artifact production, Firebreak will recreate the per-package image explosion this spec is trying to avoid
- if Darwin consumption is implemented without a clear Linux-builder or cache contract, the product could regress into hidden cross-platform build heuristics
- if CI only proves artifact production and stops proving host-runtime consumption, platform regressions will still slip through
- if CI only proves host consumption against stale artifacts, guest-production regressions could be hidden until release time
