---
status: draft
last_updated: 2026-04-05
---

# 018 Warm Local Command Channel

## Problem

Runtime v2 has removed several cold-boot taxes, but the dominant remaining cost is architectural.

Firebreak still treats "run one command" as "boot one VM". That means:

- each local command launch pays guest boot and runtime attachment costs
- worker VM mode still creates more VM lifetimes instead of reusing a prepared instance
- Cloud Hypervisor snapshot support cannot deliver meaningful wins yet, because the current command model is still tied to boot-time session setup

Snapshotting a booted VM is only useful once Firebreak can inject commands into a running local instance without rebooting it.

## Goals

- separate local VM lifetime from per-command session lifetime
- allow the host to send commands into a running local VM through a backend-private command channel
- keep the public `firebreak run` and worker UX stable while changing the runtime internals
- prepare the Cloud Hypervisor local backend for snapshot restore and warm pools
- keep the implementation replacement-first and Linux-local-only until the contract is proven

## Non-goals

- adding a second public runtime profile
- exposing warm-instance plumbing as a public hypervisor feature matrix
- preserving the old "every command boots a fresh VM" path as a compatibility layer once warm reuse is accepted
- solving the future cloud backend in this changeset

## Requirements

- the local Linux backend shall support a host-to-guest command channel that does not require a fresh VM boot per request
- the command channel shall be backend-private and shall not change the public Firebreak CLI shape
- the host shall be able to detect whether a reusable local instance is alive before dispatching a command
- local command dispatch shall fail clearly if the requested command channel is unavailable
- the system shall not silently fall back from warm-instance dispatch to weaker semantics when the caller explicitly requested a warm path
- the command channel shall preserve current stdout, stderr, exit-code, and attach semantics
- the local backend shall support a detached VM lifetime so a running instance can outlive one host wrapper process
- the design shall prepare for Cloud Hypervisor snapshot restore after a reusable running-instance command path exists

## Proposed shape

### Guest side

- introduce a dedicated local command-service inside the guest
- the command service owns command execution, status files, attach streams, and exit-code materialization
- boot-time guest preparation becomes "bring the guest to ready state", not "run exactly one command and exit"

### Host side

- introduce a backend-private local instance controller for Linux Cloud Hypervisor
- the controller is responsible for:
  - acquiring an exclusive lease on the reusable instance directory and command channel before probing, starting, or dispatching
  - renewing that lease while it owns the warm instance
  - releasing the lease on normal exit and cleaning up stale lease state after crash detection
  - probing whether an instance is alive
  - starting a detached instance when needed
  - dispatching command requests into the guest command channel
  - collecting stdout, stderr, attach streams, and exit codes
  - stopping or snapshotting the instance when policy requires it

### Snapshot phase

- after the command channel exists, add snapshot preparation and restore for the local Linux Cloud Hypervisor backend
- snapshots shall restore a ready guest that is waiting for host commands, not a one-shot boot path that still assumes boot-time command injection

## Acceptance criteria

- a local Linux Firebreak workload can execute multiple host-dispatched commands against one VM lifetime
- the host wrapper can distinguish "start instance" from "dispatch command"
- warm local command dispatch preserves current output and attach behavior
- Cloud Hypervisor snapshot integration can target a ready command-service state rather than the old boot-coupled session path

## Risks

- command-service design could accidentally duplicate existing worker bridge and exec-output logic instead of consolidating it
- detached instance ownership could become unclear if multiple host processes compete for the same instance directory
- stale lease takeover needs a conservative detect-stale path so one host process does not trample another healthy controller
- snapshot restore could paper over a weak command-channel design instead of simplifying it
