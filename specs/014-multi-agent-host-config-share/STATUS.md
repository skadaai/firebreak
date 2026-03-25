---
status: in_progress
last_updated: 2026-03-25
---

# 014 Status

## Current phase

Initial implementation in progress.

## What has landed

- a tracked spec, plan, status record, and acceptance file for the multi-agent host config share contract
- the local profile now exposes a dedicated shared host config root transport for multi-agent sandboxes
- the local host wrapper now exports one guest-readable env file for multi-agent selector defaults instead of one metadata file per key
- the shared base runtime now generates Firebreak-aware per-agent wrapper commands that translate Firebreak selector modes into agent-native config env vars
- the guest mount flow for the multi-agent host root is now part of session preparation instead of a separate dedicated mount service
- the packaged Node CLI layer now consumes the shared runtime contract instead of owning a separate multi-agent implementation
- the external agent-orchestrator recipe now declares Codex and Claude Code wrappers through that shared mechanism

## What remains open

- validation coverage for the new multi-agent config behavior
- documentation for the shared host-root interface and directory naming rules
- deciding whether per-agent host-path overrides belong in a later follow-up at all
- extending the shared wrapper mechanism cleanly to more recipes and agent families

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)

## History

- 2026-03-24: Created this spec to define how one Firebreak sandbox can host multiple agent CLIs while still honoring Firebreak config selectors in `host` mode.
- 2026-03-24: Implemented the first slice with the dedicated shared host config transport in the local profile, wrapper generation in the shared base runtime, and adoption in the external agent-orchestrator recipe.
- 2026-03-25: Simplified the first slice to one `agentVm.multiAgentConfig` subtree, one guest env file for selector defaults, and session-prep-owned mounting instead of a separate mount service.
