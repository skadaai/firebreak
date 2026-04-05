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
   - workspace resolves to `/run/firebreak-state-root/workspaces/<project-key>/codex`
   - host resolves to `/run/firebreak-state-root/codex`
   - vm resolves to `/var/lib/dev/.firebreak/codex`
   - `FIREBREAK_LAUNCH_MODE=shell` still works

5. Validate the dedicated Claude Code smoke against `workspace`, `vm`, `host`, and shell-mode resolution.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-test-smoke-claude-code"
   ```

   Expected result:
   - smoke exits `0`
   - workspace resolves to `/run/firebreak-state-root/workspaces/<project-key>/claude`
   - host resolves to `/run/firebreak-state-root/claude`
   - vm resolves to `/var/lib/dev/.firebreak/claude`
   - `FIREBREAK_LAUNCH_MODE=shell` still works

## Manual Checks

1. Verify first-run host adoption for the dedicated VMs.

   Preconditions:
   - `~/.firebreak/codex` and `~/.firebreak/claude` do not exist
   - `~/.codex` and/or `~/.claude` do exist

   Run:

   ```sh
   FIREBREAK_STATE_MODE=host FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-codex"
   ```

   ```sh
   FIREBREAK_STATE_MODE=host FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD#firebreak-claude-code"
   ```

   Confirm:
   - Firebreak prints the adoption message
   - `~/.firebreak/codex -> ~/.codex` and `~/.firebreak/claude -> ~/.claude` are created
   - adoption happens only in `host` mode

2. Verify `workspace` isolates runtime state per project while leaving native project config to the mounted workspace.

   Run either dedicated VM or the external orchestrator with `FIREBREAK_STATE_MODE=workspace`.

   Confirm:
   - the resolved runtime state directory lives under `/run/firebreak-state-root/workspaces/<project-key>/...`
   - Firebreak does not create `.firebreak/codex` or `.firebreak/claude` in the project
   - any native `.codex` or `.claude` directory already present in the repo remains the one the tool sees from cwd

3. Verify the external shared sandbox honors generic and per-tool selector precedence.

   Launch:

   ```sh
   FIREBREAK_STATE_MODE=host FIREBREAK_STATE_ROOT=/tmp/firebreak-state-root FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     "path:$PWD/external/agent-orchestrator" \
     --override-input firebreak "path:$PWD"
   ```

   Inside the VM, confirm:
   - `FIREBREAK_STATE_MODE=host codex --version` uses `/run/firebreak-state-root/codex`
   - `FIREBREAK_STATE_MODE=host claude --version` uses `/run/firebreak-state-root/claude`
   - `FIREBREAK_STATE_MODE=vm CODEX_STATE_MODE=workspace codex --version` keeps the Codex override
   - `FIREBREAK_STATE_MODE=vm CLAUDE_STATE_MODE=workspace claude --version` keeps the Claude override

4. Verify `fresh` mode is isolated.

   In a dedicated VM and in the external shared sandbox, run the agent once with `fresh` mode and confirm:
   - the resolved config directory lives under `/run/firebreak-state-fresh`
   - no data is written into project-local `.firebreak/...` overlays for that run
