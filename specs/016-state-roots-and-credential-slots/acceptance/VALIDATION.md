# 016 Validation Guide

This guide lists the checks needed to validate [SPEC.md](../SPEC.md).

## Automated Checks

Run these from the `ao` checkout root.

1. Validate the project-config and doctor smoke, because the public config surface now includes state-root and credential-slot selectors.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak-test-smoke-project-config-and-doctor'
   ```

   Expected result:
   - smoke exits `0`
   - `doctor` reports runtime-state and credential-slot resolution for Codex and Claude Code

2. Validate the dedicated Codex runtime-state behavior.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak-test-smoke-codex'
   ```

   Expected result:
   - smoke exits `0`
   - the default entrypoint still works
   - `workspace`, `vm`, and `host` all resolve correctly as runtime-state roots

3. Validate the dedicated Claude Code runtime-state behavior.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak-test-smoke-claude-code'
   ```

   Expected result:
   - smoke exits `0`
   - the default entrypoint still works
   - `workspace`, `vm`, and `host` all resolve correctly as runtime-state roots

4. Validate the shared credential-slot contract end to end.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak-test-smoke-credential-slots'
   ```

   Expected result:
   - smoke exits `0`
   - file bindings, env bindings, and helper bindings all resolve from the selected slot
   - login-to-slot writes directly into the selected slot
   - a per-tool slot override works alongside the guest-wide default slot
   - `workspace` mode uses isolated runtime state under the shared host state root rather than creating a Firebreak-owned project overlay

5. Validate the real Codex wrapper wiring against credential slots.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak-test-smoke-codex-credential-slots'
   ```

   Expected result:
   - smoke exits `0`
   - the real Firebreak Codex wrapper reads file and env credential bindings from the selected slot
   - `CODEX_CREDENTIAL_SLOT` overrides the guest-wide default slot
   - the real Firebreak Codex wrapper writes login output directly into the selected slot root

6. Validate the real Claude Code wrapper wiring against credential slots.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak-test-smoke-claude-code-credential-slots'
   ```

   Expected result:
   - smoke exits `0`
   - the real Firebreak Claude Code wrapper reads file and env credential bindings from the selected slot
   - `CLAUDE_CREDENTIAL_SLOT` overrides the guest-wide default slot
   - the real Firebreak Claude Code wrapper writes login output directly into the selected slot root

7. Validate that the shared fixture package evaluates.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     '.#packages.x86_64-linux.firebreak-credential-fixture.name'
   ```

   Expected result:
   - prints `firebreak-credential-fixture`

8. Validate the new real-wrapper smoke packages evaluate.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     '.#packages.x86_64-linux.firebreak-test-smoke-codex-credential-slots.name'
   ```

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     '.#packages.x86_64-linux.firebreak-test-smoke-claude-code-credential-slots.name'
   ```

   Expected result:
   - prints `firebreak-test-smoke-codex-credential-slots`
   - prints `firebreak-test-smoke-claude-code-credential-slots`

9. Validate the external orchestrator recipe still evaluates against the current Firebreak input.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw \
     '.#packages.x86_64-linux.firebreak-agent-orchestrator.name' \
     --override-input firebreak 'path:/home/zvictor/development/firebreak/ao'
   ```

   Run that command from `external/agent-orchestrator`.

   Expected result:
   - prints `firebreak-agent-orchestrator`

## Manual Checks

1. Verify native project config remains native project config.

   Preconditions:
   - create a repo with a real native project config folder such as `.codex/` or `.claude/`

   Run a dedicated VM with `FIREBREAK_STATE_MODE=workspace`.

   Confirm:
   - the tool still sees the native project folder from the mounted workspace
   - Firebreak does not create or manage a replacement `.firebreak/<tool>` project overlay

2. Verify `workspace` isolates runtime state without changing project config semantics.

   Launch the same tool in two different repos with `FIREBREAK_STATE_MODE=workspace`.

   Confirm:
   - runtime state resolves to different project-hashed directories under the shared state root
   - project-local native config still comes from each repo's own mounted working tree

3. Verify slot-driven credential switching preserves working context.

   In one repo, launch the same tool twice with the same state mode but different credential slots.

   Confirm:
   - the runtime-state root stays the same
   - only the selected credential material changes

4. Verify the user-facing docs are clear about the non-native parts of the model.

   Review:
   - `README.md`
   - `guides/state-roots-and-credential-slots.md`

   Confirm:
   - they clearly separate native project config, Firebreak runtime state, and credential slots
   - they explain that Firebreak intentionally differs from each tool's native config model only at the state/credential layer
