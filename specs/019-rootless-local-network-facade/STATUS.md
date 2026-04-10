---
status: draft
last_updated: 2026-04-06
---

# 019 Rootless Local Network Facade Status

## Current phase

Slice 3 is complete.

## What is landed

- the networking problem is now explicitly scoped as a capability split rather than as one coarse local-runtime requirement
- runtime backends now distinguish `guest-egress`, `host-port-publish-tcp`, and `full-guest-network` instead of one coarse local networking capability
- the local profile no longer requires privileged host networking as part of its baseline capability contract
- launcher-level Linux host-network preflight has been removed
- Cloud Hypervisor host-side networking setup is now conditional and only runs when a launch explicitly requests it
- guest runtime network configuration is now a no-op when no host networking metadata was prepared
- Cloud Hypervisor local guest egress now uses a rootless host proxy and guest relay over `vsock`
- Cloud Hypervisor local TCP publishing now uses a rootless host listener and guest relay over `vsock`
- the shared local wrapper now keeps rootless publishing separate from privileged full guest networking
- dedicated host-side smokes cover the rootless egress helper and the rootless TCP publish helper
- a real forwarded-port workload now passes end to end on the rootless publish path
- validation now distinguishes rootless local Cloud Hypervisor suites from privileged full-guest-network suites

## What remains open

- deciding the final role of privileged `full-guest-network`
- expanding snapshot and warm-instance reuse on top of the rootless local networking facade
