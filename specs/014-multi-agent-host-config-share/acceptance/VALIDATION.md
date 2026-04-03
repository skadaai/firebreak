# 014 Validation Guide

This guide lists the checks needed to validate [SPEC.md](../SPEC.md).

## Automated Checks

1. Validate the dedicated Codex package still evaluates under the shared host-root contract.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     "path:$PWD#packages.x86_64-linux.firebreak-codex.name"
   ```

   Expected result:
   - prints `firebreak-codex`

2. Validate the dedicated Claude Code package still evaluates under the shared host-root contract.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     "path:$PWD#packages.x86_64-linux.firebreak-claude-code.name"
   ```

   Expected result:
   - prints `firebreak-claude-code`

3. Validate the external shared sandbox recipe still evaluates with the shared wrapper wiring.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     "path:$PWD/external/agent-orchestrator#packages.x86_64-linux.firebreak-agent-orchestrator.name" \
     --override-input firebreak "path:$PWD"
   ```

   Expected result:
   - prints `firebreak-agent-orchestrator`

4. Validate the dedicated Codex smoke against `workspace`, `vm`, `host`, and shell-mode resolution.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-test-smoke-codex"
   ```

   Expected result:
   - smoke exits `0`
   - workspace resolves to `.firebreak/codex`
   - host resolves to `/run/agent-config-host-root/codex`
   - vm resolves to `/var/lib/dev/.firebreak/codex`
   - `FIREBREAK_LAUNCH_MODE=shell` still works

5. Validate the dedicated Claude Code smoke against `workspace`, `vm`, `host`, and shell-mode resolution.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-test-smoke-claude-code"
   ```

   Expected result:
   - smoke exits `0`
   - workspace resolves to `.firebreak/claude`
   - host resolves to `/run/agent-config-host-root/claude`
   - vm resolves to `/var/lib/dev/.firebreak/claude`
   - `FIREBREAK_LAUNCH_MODE=shell` still works

## Manual Checks

1. Verify first-run host adoption for the dedicated VMs.

   Preconditions:
   - `~/.firebreak/codex` and `~/.firebreak/claude` do not exist
   - `~/.codex` and/or `~/.claude` do exist

   Run:

   ```sh
   AGENT_CONFIG=host FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-codex"
   ```

   ```sh
   AGENT_CONFIG=host FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-claude-code"
   ```

   Confirm:
   - Firebreak prints the adoption message
   - `~/.firebreak/codex -> ~/.codex` and `~/.firebreak/claude -> ~/.claude` are created
   - adoption happens only in `host` mode

2. Verify `workspace` stays project-local and does not symlink into the shared host root.

   Run either dedicated VM or the external orchestrator with `AGENT_CONFIG=workspace`.

   Confirm:
   - `.firebreak/codex` and `.firebreak/claude` are real project-local directories
   - they are not symlinks to `~/.firebreak`, `~/.codex`, or `~/.claude`

3. Verify the external shared sandbox honors generic and per-agent selector precedence.

   Launch:

   ```sh
   AGENT_CONFIG=host AGENT_CONFIG_HOST_PATH=/tmp/firebreak-agent-share FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD/external/agent-orchestrator" \
     --override-input firebreak "path:$PWD"
   ```

   Inside the VM, confirm:
   - `AGENT_CONFIG=host codex --version` uses `/run/agent-config-host-root/codex`
   - `AGENT_CONFIG=host claude --version` uses `/run/agent-config-host-root/claude`
   - `AGENT_CONFIG=vm CODEX_CONFIG=workspace codex --version` keeps the Codex override
   - `AGENT_CONFIG=vm CLAUDE_CONFIG=workspace claude --version` keeps the Claude override

4. Verify `fresh` mode is isolated.

   In a dedicated VM and in the external shared sandbox, run the agent once with `fresh` mode and confirm:
   - the resolved config directory lives under `/run/firebreak-agent-config-fresh`
   - no data is written into `.firebreak/...` or the shared host root for that run
