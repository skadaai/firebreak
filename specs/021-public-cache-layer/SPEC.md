---
status: draft
last_updated: 2026-04-08
---

# 021 Public Cache Layer

## Problem

Firebreak now has two clearly separate latency buckets:

- outer Nix evaluation, build, and substitution cost
- inner guest boot and command startup cost

Recent measurements show that the outer build/substitution path is still painful in several common flows:

- `nix run .#firebreak-codex -- --version`
- nested `codex --version` and `claude --version` launched through Agent Orchestrator
- first-use realization of common Firebreak packages on a new machine

This cost is often much larger than the VM startup cost itself. It is also the highest-ROI experimental improvement available because it can remove minutes of repeated local work without changing guest runtime semantics.

## Goals

- make Firebreak user-facing packages substitute from a public binary cache by default when the user machine is configured to trust that cache
- maximize cache hits for the common local packages and nested worker package paths
- separate cache-layer concerns from boot-base and environment-overlay concerns
- keep cache population reproducible, explicit, and CI-driven
- improve first-use and repeated-use latency without weakening Firebreak's runtime boundaries

## Non-goals

- treating the cache layer as a replacement for guest boot optimization
- making Firebreak depend on one specific cache provider
- silently bypassing Nix signature verification
- caching arbitrary mutable runtime state, workspace data, or credential material
- hiding build failures behind best-effort fallbacks

## Direction

Firebreak should add a public binary cache layer for reproducible build artifacts, not for runtime state.

The cache layer should cover at least:

- user-facing `nix run` packages such as `firebreak`, `firebreak-codex`, and `firebreak-claude-code`
- common runner and smoke packages needed by CI and local validation
- nested worker launch packages used from inside orchestrated shells
- common system closures that are expensive and stable enough to benefit from remote substitution

The cache layer is additive:

- if a trusted substitute exists, users download rather than build
- if not, Nix still builds locally
- Firebreak runtime semantics stay unchanged

## Product model

Firebreak should treat cache distribution as a host artifact-distribution concern with three pieces:

1. output shape
   - package and check outputs should be structured so the same installables are reused by local launchers, nested worker launchers, and CI

2. cache population
   - CI or controlled builders should realize and push the relevant outputs

3. trust and consumption
   - users who configure the cache as trusted get substitution
   - users who do not still have a correct local-build path

## Cache contract

The public cache layer shall:

- cache only reproducible derivation outputs
- require signature verification and published public keys
- preserve system-specific package identity rather than pretending artifacts are portable when they are not
- prioritize high-traffic installables over broad speculative cache coverage

The cache layer should be designed around the installables users actually hit:

- `packages.<system>.firebreak`
- `packages.<system>.firebreak-codex`
- `packages.<system>.firebreak-claude-code`
- orchestrator-facing nested worker packages that resolve to those same installables
- core supporting outputs needed to avoid rebuilding wrappers, runners, and stable system closures

## Requirements

- Firebreak shall define a canonical set of high-value installables to populate in the public cache.
- Firebreak shall keep those installables stable and explicit enough that local and nested launch paths resolve to the same derivations whenever possible.
- Firebreak shall preserve system-specific output identities so substitution works correctly across supported systems.
- Firebreak shall require signed cache artifacts and documented public keys.
- Firebreak shall keep cache consumption optional at the Nix trust layer while making it easy to opt in.
- Firebreak shall not rely on guest-time package installation to benefit from the cache layer.
- Firebreak shall prefer reusing already-cached user-facing packages over constructing parallel derivations for nested launcher paths.
- Firebreak shall make cache misses observable rather than silent.

## Proposed implementation shape

### 1. Canonical installable surface

- audit current flake outputs
- identify the exact installables users and nested worker flows resolve today
- reduce avoidable divergence between:
  - direct `nix run .#firebreak-codex`
  - nested worker package launches
  - CI smoke and validation paths

### 2. Cache metadata and trust

- publish a documented substituter URL and public signing key
- wire the cache into Firebreak-facing documentation and doctor output
- keep substitution opt-in at the host trust layer rather than forcing restricted Nix settings

### 3. Cache population pipeline

- define the package/check matrix to build and push from CI or controlled builders
- filter out low-value or impure artifacts
- prioritize stable, expensive, frequently reused outputs

### 4. Nested-launch alignment

- ensure nested worker launch paths reuse the same canonical package outputs instead of creating avoidable parallel derivations
- make wrapper scripts and orchestrator recipes point at the same package identities the outer CLI uses

### 5. Observability

- make `firebreak doctor` surface cache configuration, trust state, and likely cache-miss causes
- keep it obvious when a path is rebuilding locally instead of substituting

## Acceptance criteria

- a trusted-user machine with the Firebreak public cache configured can run the common Firebreak installables without rebuilding them when the artifacts are already present in cache
- nested worker launches from orchestrated shells reuse the same cached package identities as direct outer launches where semantics are equivalent
- the repository documents the canonical cache surface and how it is populated
- cache trust and substitution status are inspectable through Firebreak diagnostics
- Firebreak still works correctly without the public cache, but with a slower local-build path

## Dependencies and risks

### Dependencies

- [specs/017-runtime-v2/SPEC.md](../017-runtime-v2/SPEC.md)
- [specs/020-minimal-boot-bases-and-environment-overlays/SPEC.md](../020-minimal-boot-bases-and-environment-overlays/SPEC.md)
- [ARCHITECTURE.md](../../ARCHITECTURE.md)
- [AGENTS.md](../../AGENTS.md)

### Risks

- caching the wrong installables would leave the hottest user-facing paths rebuilding anyway
- too many slightly different output identities would dilute cache effectiveness
- undocumented trust requirements would make the cache feel broken to end users
- focusing only on cache work could hide the still-open guest boot bottleneck
