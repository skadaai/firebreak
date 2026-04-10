---
status: active
last_updated: 2026-04-08
---

# 021 Public Cache Layer Status

## Current phase

Design definition.

## What is known now

- Firebreak has a real outer build/substitution latency problem in addition to guest boot latency.
- A public binary cache is the highest-ROI next step for reducing repeated local build cost during the experimental phase.
- The cache layer should target canonical user-facing package outputs and nested worker package paths first.
- Cache work will not solve the remaining guest boot bottleneck by itself.
- On untrusted-user machines, Nix may ignore configured substituters and `trusted-public-keys`, so cache diagnostics need to distinguish host trust-state problems from ordinary cache misses.

## What remains open

- defining the exact first-wave cache surface
- deciding the initial cache population matrix
- aligning nested worker launches with canonical cached package identities
- adding cache trust and miss diagnostics to Firebreak surfaces
