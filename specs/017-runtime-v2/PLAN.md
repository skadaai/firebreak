---
status: draft
last_updated: 2026-04-05
---

# 017 Runtime V2 Plan

## Current status

Runtime v2 is at the design-definition stage.

The intended direction is an aggressive replacement of Linux local QEMU with a Cloud Hypervisor-based local runtime, while keeping product profiles stable and private runtime backends explicit.

## Implementation slices

### Slice 1: backend capability contract

- define a shared backend interface in runtime support code
- move hypervisor-specific invocation and attachment logic behind that interface
- keep `local` and `cloud` as the only product profiles
- make unsupported capability combinations fail explicitly

### Slice 2: Linux local Cloud Hypervisor backend

- implement a Cloud Hypervisor backend for the local Linux profile
- replace Linux local `9p` assumptions with `virtiofs`-based attachments where required
- preserve local interactive console semantics
- preserve local workspace access

### Slice 3: Linux local port publishing replacement

- replace QEMU `forwardPorts` user-network forwarding with a host-owned Linux port publishing layer suitable for Cloud Hypervisor networking
- keep the public `forwardPorts` contract intact for supported local Linux use cases
- keep the implementation Linux-only and explicit rather than abstracting speculative unsupported cases

### Slice 4: local boot-path reduction

- remove hot-path boot dependencies that are not required for prepared local launches
- remove runtime package installation from the critical startup path
- prepare the local runtime for snapshot- or warm-instance-oriented startup

### Slice 5: aggressive deletion

- delete Linux local QEMU runtime selection and related compatibility logic
- delete QEMU-specific local docs and validation once Cloud Hypervisor replaces them
- remove QEMU from Firebreak runtime support entirely unless a separately specified surviving contract still requires it

### Slice 6: future cloud backend definition

- define the cloud profile against image, volume, and snapshot semantics
- choose and implement a cloud-oriented backend separately from the local replacement work
- do not allow future cloud requirements to weaken the local runtime contract

## Validation approach

- backend contract tests for capability satisfaction and explicit rejection
- Linux local smoke coverage on Cloud Hypervisor
- local workspace mount validation
- local port publishing validation for current `from = "host"` cases
- focused boot-latency validation for repeated prepared launches
- removal of Linux local QEMU validation from the main support matrix once replacement lands

## Deletion policy

- do not keep a compatibility toggle for Linux local QEMU after Cloud Hypervisor becomes the supported Linux local runtime
- do not keep fallback code paths that silently downgrade unsupported capability combinations
- prefer deleting dead runtime code in the same changeset that makes it obsolete
- prefer replacement-sized changesets over compatibility-preserving incrementalism

## Open questions

- whether the Linux local port publishing implementation should be a userland proxy, kernel NAT rules, or a smaller dedicated forwarding helper
- whether the first Cloud Hypervisor local rollout should require snapshot support or can land first as a cold-boot improvement before snapshotting
- whether worker fast-start should share the same prepared-instance mechanism as ordinary local launches or use a separate pool implementation
