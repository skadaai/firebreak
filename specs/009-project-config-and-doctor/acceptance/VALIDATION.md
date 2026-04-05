# 009 Validation Guide

This guide lists the checks needed to validate [SPEC.md](../SPEC.md).

## Automated Checks

Run these from the flake root. If you are elsewhere, replace `.` with the repository root explicitly.

1. Validate the project-config and doctor smoke end-to-end.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     ".#firebreak-test-smoke-project-config-and-doctor"
   ```

   Expected result:
   - smoke exits `0`
   - `.firebreak.env` generation, allowlisting, env-overrides-file precedence, and `doctor` summary/json/verbose behavior all pass

2. Validate the top-level Firebreak CLI package still evaluates.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     ".#packages.x86_64-linux.firebreak.name"
   ```

   Expected result:
   - prints `firebreak`

3. Validate the dedicated Codex package still evaluates with the current config contract.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     ".#packages.x86_64-linux.firebreak-codex.name"
   ```

   Expected result:
   - prints `firebreak-codex`

4. Validate the dedicated Claude Code package still evaluates with the current config contract.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     ".#packages.x86_64-linux.firebreak-claude-code.name"
   ```

   Expected result:
   - prints `firebreak-claude-code`

## Manual Checks

1. Verify `firebreak init` writes the expected host-default template.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     ".#firebreak" -- init --stdout
   ```

   Confirm:
   - the output uses `.firebreak.env`
   - the template defaults to `FIREBREAK_STATE_MODE=host`
   - the template does not mention `FIREBREAK_AGENT_MODE`, `AGENT_VM_ENTRYPOINT`, `CODEX_CONFIG_HOST_PATH`, or `CLAUDE_CONFIG_HOST_PATH`

2. Verify `firebreak doctor` reflects the resolved host-root-plus-subdir model.

   ```sh
   FIREBREAK_STATE_MODE=host FIREBREAK_STATE_ROOT=~/.firebreak \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     ".#firebreak" -- doctor --verbose
   ```

   Confirm:
   - Codex resolves to a `codex` subdirectory under the shared host root
   - Claude resolves to a `claude` subdirectory under the shared host root
   - `doctor` reports KVM and cwd compatibility state

3. Verify the public local mode selector is only `FIREBREAK_LAUNCH_MODE`.

   Launch one public VM with `FIREBREAK_LAUNCH_MODE=shell` and confirm shell mode works.
   Confirm the docs and output do not instruct users to use `FIREBREAK_AGENT_MODE` or `AGENT_VM_ENTRYPOINT`.
