status: completed
last_updated: 2026-04-04
---

# 014 Status

## Current phase

Implemented.

## What has landed

- a tracked spec, plan, status record, and acceptance file for the shared state-root contract
- the local profile now exposes a dedicated shared host state-root transport for shared-sandbox workloads
- the dedicated Codex and Claude Code local packages now use that same shared host root with stable `codex` and `claude` subdirectories
- dedicated Bun-backed workloads and shared wrappers now share one guest-side state resolver instead of keeping separate path-resolution logic
- the local host wrapper now exports one guest-readable env file for shared selector defaults instead of one metadata file per key
- the shared base runtime now generates Firebreak-aware per-tool wrapper commands that translate Firebreak selector modes into tool-native config env vars
- the guest mount flow for the shared host root is now part of session preparation instead of a separate dedicated mount service
- the packaged Node CLI layer now consumes the shared runtime contract instead of owning a separate sandbox-specific implementation
- the external agent-orchestrator recipe now declares Codex and Claude Code wrappers through that shared mechanism
- `workspace` mode now stays project-local instead of being bootstrapped as a symlink into the shared host root
- automated validation now covers the dedicated Codex and Claude Code shared-root paths plus the external orchestrator evaluation path
- user-facing docs now describe the shared-root contract in clearer language alongside the newer state-root/credential-slot model

## What remains open

- extending the shared wrapper mechanism cleanly to more recipes and tool families

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec to define how one Firebreak sandbox can host multiple tool CLIs while still honoring Firebreak state selectors in `host` mode.
- 2026-03-24: Implemented the first slice with the dedicated shared host state transport in the local profile, wrapper generation in the shared base runtime, and adoption in the external agent-orchestrator recipe.
- 2026-03-25: Simplified the first slice to one `workloadVm.sharedStateRoots` subtree, one guest env file for selector defaults, and session-prep-owned mounting instead of a separate mount service.
- 2026-03-25: Unified dedicated Codex and Claude Code local packages onto the same host-root-plus-subdirectory contract and removed per-tool host-path variables from the public state surface.
- 2026-03-25: Collapsed dedicated Bun-backed workloads onto the same shared guest-side resolver used by generated wrappers, and constrained legacy config adoption to `host` mode only.
- 2026-04-04: Added focused validation coverage and user-facing documentation that explains the shared-root contract as part of the broader state-root model.
