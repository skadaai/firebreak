---
status: draft
last_updated: 2026-04-05
---

# 018 Warm Local Command Channel Plan

## Current status

Warm non-interactive local command reuse is partially landed. Remaining work is validation, hardening, attached warm dispatch, and snapshots.

## Implementation slices

### Slice 1: command-service contract

- define the guest-local command-service interface and request/response file layout
- align it with current stdout, stderr, attach, and exit-code semantics
- delete overlapping boot-coupled command materialization where possible

### Slice 2: detached instance controller

- add a host-side local instance controller for Linux Cloud Hypervisor
- separate "ensure instance is running" from "dispatch command"
- make stale or unavailable command channels fail explicitly

### Slice 3: warm command dispatch

- route local host command execution through the running instance when available
- preserve current attach and non-attach behavior
- keep explicit cold-boot behavior only where the product contract still requires it

### Slice 4: snapshot preparation and restore

- add snapshot prepare/restore for the ready local command-service state
- measure repeated command startup against cold boot
- keep the snapshot path backend-private to Linux local Cloud Hypervisor

## Validation approach

- contract tests for command request, response, attach, and exit-code behavior
- repeated-command latency comparison against current cold-boot behavior
- running-instance reuse tests for worker and top-level local command paths
- snapshot prepare/restore smoke once the detached instance controller exists
