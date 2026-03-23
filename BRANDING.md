Skada Firebreak
Short name: Firebreak
Tagline: reliable isolation for high-trust automation

Public naming:
- Top-level CLI/control plane: firebreak
- Codex VM entry: firebreak-codex
- Codex maintenance shell override: AGENT_VM_ENTRYPOINT=shell nix run .#firebreak-codex
- Codex smoke test entry: firebreak-test-smoke-codex
- Claude Code VM entry: firebreak-claude-code
- Claude Code maintenance shell override: AGENT_VM_ENTRYPOINT=shell nix run .#firebreak-claude-code
- Claude Code smoke test entry: firebreak-test-smoke-claude-code
- Current shipped agent VMs: firebreak-codex, firebreak-claude-code

Branding rules:
- Prefer "Skada Firebreak" in human-facing copy.
- Prefer "Firebreak" in product references and short UI strings.
- Keep agent-specific identities explicit when needed, for example "firebreak-codex".
- Do not use bare `firebreak` as the name of a specific VM.
