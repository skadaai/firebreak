# Firebreak Manual Validation Batch

Run this batch after the automated checks in [VALIDATION.md](./VALIDATION.md) are green.

These checks cover the remaining human-facing behavior across:
- [spec 009](../../009-project-config-and-doctor/SPEC.md)
- [spec 014](../../014-multi-agent-host-config-share/SPEC.md)
- [spec 016](../SPEC.md)

## Setup

Run from the `ao` checkout root unless a step says otherwise.

Prepare two throwaway repos so `workspace` isolation can be checked cleanly:

```sh
tmp_root=$(mktemp -d)
repo_a="$tmp_root/repo-a"
repo_b="$tmp_root/repo-b"
mkdir -p "$repo_a" "$repo_b"
git -C "$repo_a" init -q
git -C "$repo_b" init -q
```

## Batch 1: Public Config Surface

1. Inspect the init template.

   ```sh
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak' -- init --stdout
   ```

   Confirm:
   - the template uses `.firebreak.env`
   - the template defaults to `AGENT_CONFIG=host`
   - the template includes credential-slot examples
   - the template does not mention `CODEX_CONFIG_HOST_PATH` or `CLAUDE_CONFIG_HOST_PATH`

2. Inspect doctor output.

   ```sh
   AGENT_CONFIG=host \
   AGENT_CONFIG_HOST_PATH="$HOME/.firebreak" \
   FIREBREAK_CREDENTIAL_SLOT=default \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     '.#firebreak' -- doctor --verbose
   ```

   Confirm:
   - Codex resolves to the `codex` subdirectory under the shared host root
   - Claude resolves to the `claude` subdirectory under the shared host root
   - Codex and Claude credential slots/paths are shown
   - KVM and cwd diagnostics are still present

## Batch 2: Native Project Config Versus Firebreak State

1. Add native project config markers.

   ```sh
   mkdir -p "$repo_a/.codex" "$repo_a/.claude"
   printf '%s\n' 'native-codex-config' > "$repo_a/.codex/firebreak-marker.txt"
   printf '%s\n' 'native-claude-config' > "$repo_a/.claude/firebreak-marker.txt"
   ```

2. Launch Codex in `workspace` mode.

   ```sh
   (
     cd "$repo_a"
     AGENT_CONFIG=workspace FIREBREAK_LAUNCH_MODE=shell \
     nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
       'path:/home/zvictor/development/firebreak/ao#firebreak-codex'
   )
   ```

   Inside the VM, confirm:
   - `pwd` is the repo path
   - `test -f .codex/firebreak-marker.txt`
   - `printf '%s\n' "$CODEX_HOME"`
   - `printf '%s\n' "$AGENT_CONFIG_DIR"`
   - neither path is `.codex`
   - `test ! -e .firebreak/codex`

3. Launch Claude Code in `workspace` mode.

   ```sh
   (
     cd "$repo_a"
     AGENT_CONFIG=workspace FIREBREAK_LAUNCH_MODE=shell \
     nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
       'path:/home/zvictor/development/firebreak/ao#firebreak-claude-code'
   )
   ```

   Inside the VM, confirm:
   - `test -f .claude/firebreak-marker.txt`
   - `printf '%s\n' "$CLAUDE_CONFIG_DIR"`
   - `printf '%s\n' "$AGENT_CONFIG_DIR"`
   - neither path is `.claude`
   - `test ! -e .firebreak/claude`

## Batch 3: Workspace State Isolation

1. Launch the same tool in two repos.

   ```sh
   (
     cd "$repo_a"
     AGENT_CONFIG=workspace FIREBREAK_LAUNCH_MODE=shell \
     nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
       'path:/home/zvictor/development/firebreak/ao#firebreak-codex'
   )
   ```

   ```sh
   (
     cd "$repo_b"
     AGENT_CONFIG=workspace FIREBREAK_LAUNCH_MODE=shell \
     nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
       'path:/home/zvictor/development/firebreak/ao#firebreak-codex'
   )
   ```

   In each VM, record `CODEX_HOME`.

   Confirm:
   - the two `CODEX_HOME` values differ
   - both are under the shared runtime-state root
   - the project-local `.codex` semantics remain unchanged

## Batch 4: Host Adoption And Credential Switching

1. Verify first-run host adoption for Codex.

   Preconditions:
   - `~/.firebreak/codex` does not exist
   - `~/.codex` does exist

   Run:

   ```sh
   AGENT_CONFIG=host FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     'path:/home/zvictor/development/firebreak/ao#firebreak-codex'
   ```

   Confirm:
   - Firebreak prints the adoption message
   - `~/.firebreak/codex -> ~/.codex` is created

2. Verify first-run host adoption for Claude Code.

   Preconditions:
   - `~/.firebreak/claude` does not exist
   - `~/.claude` does exist

   Run:

   ```sh
   AGENT_CONFIG=host FIREBREAK_LAUNCH_MODE=shell \
   nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
     'path:/home/zvictor/development/firebreak/ao#firebreak-claude-code'
   ```

   Confirm:
   - Firebreak prints the adoption message
   - `~/.firebreak/claude -> ~/.claude` is created

3. Verify slot-driven credential switching without changing runtime state.

   Prepare:

   ```sh
   slot_root="$tmp_root/credential-slots"
   mkdir -p "$slot_root/default/codex" "$slot_root/backup/codex"
   printf '%s\n' 'slot-default-auth' > "$slot_root/default/codex/auth.json"
   printf '%s\n' 'slot-backup-auth' > "$slot_root/backup/codex/auth.json"
   ```

   Launch the same repo twice:

   ```sh
   (
     cd "$repo_a"
     AGENT_CONFIG=workspace \
     FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$slot_root" \
     FIREBREAK_CREDENTIAL_SLOT=default \
     FIREBREAK_LAUNCH_MODE=shell \
     nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
       'path:/home/zvictor/development/firebreak/ao#firebreak-codex'
   )
   ```

   ```sh
   (
     cd "$repo_a"
     AGENT_CONFIG=workspace \
     FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH="$slot_root" \
     CODEX_CREDENTIAL_SLOT=backup \
     FIREBREAK_LAUNCH_MODE=shell \
     nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
       'path:/home/zvictor/development/firebreak/ao#firebreak-codex'
   )
   ```

   In both VMs, record `CODEX_HOME`.

   Confirm:
   - the `CODEX_HOME` value stays the same between the two runs
   - only the selected credential slot changes

## Batch 5: Documentation Clarity

Review:
- [README.md](/home/zvictor/development/firebreak/ao/README.md)
- [state-roots-and-credential-slots.md](/home/zvictor/development/firebreak/ao/guides/state-roots-and-credential-slots.md)

Confirm:
- the docs clearly separate native project config, Firebreak runtime state, and credential slots
- the docs explain that Firebreak intentionally differs from native tools only at the runtime-state and credential layers
- the docs explain the user-facing selectors with concrete examples
