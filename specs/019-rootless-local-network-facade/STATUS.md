---
status: draft
last_updated: 2026-04-06
---

# 019 Rootless Local Network Facade Status

## Current phase

Executing slice 1.

## What is landed

- the networking problem is now explicitly scoped as a capability split rather than as one coarse local-runtime requirement
- runtime backends now distinguish `guest-egress`, `host-port-publish-tcp`, and `full-guest-network` instead of one coarse local networking capability
- the local profile no longer requires privileged host networking as part of its baseline capability contract
- launcher-level Linux host-network preflight has been removed
- Cloud Hypervisor host-side networking setup is now conditional and only runs when a launch explicitly requests it
- guest runtime network configuration is now a no-op when no host networking metadata was prepared

## What remains open

- rootless `guest-egress` over `vsock`
- rootless localhost TCP publishing over `vsock`
- deciding the final role of privileged `full-guest-network`
