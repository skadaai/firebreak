---
status: draft
last_updated: 2026-04-06
---

# 019 Rootless Local Network Facade

## Problem

Linux local Firebreak now targets Cloud Hypervisor, but Cloud Hypervisor does not provide QEMU-style built-in user networking or host port forwarding.

Firebreak currently papers over that gap with a privileged tap/NAT path. That makes the default local UX too expensive:

- it requires host networking setup that does not belong in getting started
- it treats all networking needs as one coarse requirement
- it forces privileged setup even when a workload only needs outbound API access or localhost port publishing

That is the wrong product contract for Firebreak local.

## Goals

- keep Cloud Hypervisor as the Linux local backend
- keep the default local UX zero-setup for common worker and local web-app workflows
- model networking in capability terms rather than as one coarse `local-networking` requirement
- provide rootless networking for the common path
- keep privileged full guest networking explicit and opt-in

## Non-goals

- building a full Docker-style virtual networking stack in the first slice
- preserving the current privileged tap/NAT path as the default local behavior
- inventing a generic network subsystem before the minimal Firebreak needs are clear

## Capability contract

The local runtime shall model networking with explicit capabilities:

- `guest-egress`
- `host-port-publish-tcp`
- `full-guest-network`

These capabilities are intentionally different:

- `guest-egress` means guest processes can reach external APIs and services
- `host-port-publish-tcp` means Firebreak can expose a guest TCP service on `127.0.0.1:PORT`
- `full-guest-network` means the guest receives a real NIC-shaped network path with host-side setup requirements

The system shall not treat these as interchangeable.

## Intended landing shape

- local profile no longer implies `full-guest-network`
- Linux local Cloud Hypervisor boots without privileged host-network setup when no workload asks for full guest networking
- worker workloads get `guest-egress` through a rootless host/guest broker
- local TCP publishing uses a rootless host listener and guest transport path
- the existing privileged tap/NAT path, if still needed, becomes the implementation of `full-guest-network` only

## Requirements

- the local profile shall require only the capabilities that every local workload actually needs
- workloads that need outbound network access shall request `guest-egress`
- workloads that publish host ports shall request `host-port-publish-tcp`
- workloads that require a real guest NIC shall request `full-guest-network`
- the launcher shall not fail before a requested capability is known
- privileged host setup shall not be part of the default Linux local path
- unsupported capability/backend combinations shall fail explicitly

## Delivery slices

1. split the capability contract and remove premature launcher gating
2. implement rootless `guest-egress` over `vsock`
3. implement rootless `host-port-publish-tcp` over `vsock`
4. decide whether richer networking needs justify integrating an external userspace VM network layer

## Acceptance criteria

- `firebreak run codex` no longer fails in the launcher just because privileged host networking is unavailable
- the runtime contract distinguishes egress, localhost publishing, and full guest networking
- Cloud Hypervisor local networking setup is only invoked when a workload requests the capability that needs it
- the repository documents one intended rootless local networking path for the common Firebreak workflow

## Dependencies and risks

### Dependencies

- [specs/017-runtime-v2/SPEC.md](../017-runtime-v2/SPEC.md)
- [modules/profiles/local/](../../modules/profiles/local/)
- [nix/support/runtime-backends.nix](../../nix/support/runtime-backends.nix)

### Risks

- claiming `guest-egress` before the rootless broker exists would turn the capability contract into a lie
- leaving privileged network setup in the hot path would preserve the current product failure under a new name
- over-generalizing too early would turn a small agent-focused problem into a second networking product
