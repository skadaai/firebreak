---
status: draft
last_updated: 2026-04-08
---

# 021 Public Cache Layer Plan

## Current status

This changeset is at the design-definition stage.

The problem is now measured clearly:

- outer Nix build/substitution cost is a major source of user-visible latency
- guest boot cost remains a separate problem and should not be conflated with cache work

## Implementation slices

### Slice 1: canonical cache surface

- inventory the actual high-traffic Firebreak installables
- define the minimum set of packages and checks worth caching first
- document which nested worker paths should reuse those exact outputs

### Slice 2: trust and diagnostics contract

- define the public cache URL and signing-key contract
- add doctor/reporting support for cache trust state and substituter visibility
- fail clearly when a user expects substitution but their host is not configured to trust the cache

### Slice 3: CI population path

- define the builder matrix that should populate the cache
- keep the initial matrix intentionally small and high-value
- avoid pushing low-value source or evaluation artifacts

### Slice 4: nested-launch output alignment

- audit where nested worker paths currently trigger distinct derivations
- align those paths to the canonical outer package outputs where behavior is the same
- verify that AO-style nested launches hit the same cacheable package identities

### Slice 5: rollout and validation

- validate cold first-use and repeated-use timings on cache-hit paths
- document the expected behavior for trusted versus untrusted users
- keep cache misses observable through smoke tests or diagnostics

## Validation approach

- `nix path-info` and `nix run` checks on canonical packages before and after cache population
- direct versus nested launch comparisons for package identity reuse
- doctor output checks for substituter and trust-state reporting
- CI-side proof that targeted packages are realized and pushed successfully

## Out-of-scope follow-up work

- guest boot optimization remains tracked separately
- broader environment-overlay caching remains tracked separately
- provider-specific operational tuning should be documented after the cache contract is settled
