---
status: draft
last_updated: 2026-04-06
---

# 019 Rootless Local Network Facade Plan

## Slice 1

- split networking capabilities into `guest-egress`, `host-port-publish-tcp`, and `full-guest-network`
- remove launcher-level Linux host-network preflight
- make Cloud Hypervisor host networking setup conditional instead of unconditional

## Slice 2

- add a rootless host egress broker
- attach it to Cloud Hypervisor guests over `vsock`
- wire guest agent workloads through proxy environment variables

## Slice 3

- add rootless localhost TCP publishing over `vsock`
- move node-cli forwardPorts to the new capability contract
- keep the scope to TCP localhost publishing only

## Slice 4

- decide whether to keep the privileged `full-guest-network` path
- if richer networking is still needed, evaluate an external userspace VM networking layer instead of building one from scratch
- `containers/gvisor-tap-vsock` is the first candidate to evaluate for this role
