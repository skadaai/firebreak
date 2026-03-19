# Architecture

Firebreak uses a module-oriented layout instead of flat `scripts/` and `tests/` buckets.

## Structure

- [`modules/base/`](./modules/base): shared VM runtime.
  - [`module.nix`](./modules/base/module.nix): common NixOS MicroVM behavior.
  - [`host/`](./modules/base/host): host-side wrapper and runtime argument helpers.
  - [`guest/`](./modules/base/guest): guest-side boot, session, and shell helpers.
  - [`tests/`](./modules/base/tests): generic smoke templates owned by the base runtime.
- [`modules/bun-agent/`](./modules/bun-agent): shared implementation for Bun-managed agent CLIs.
  - [`module.nix`](./modules/bun-agent/module.nix): common Bun-agent overlay logic.
  - [`guest/`](./modules/bun-agent/guest): guest bootstrap and shell-init templates for Bun-backed agents.
- [`modules/codex/`](./modules/codex): Codex-specific overlay.
- [`modules/claude-code/`](./modules/claude-code): Claude Code-specific overlay.

## Separation Of Concerns

- `modules/base` owns VM lifecycle, workspace mounting, host/guest identity mapping, session preparation, and console behavior.
- `modules/bun-agent` owns the shared contract for agents launched through Bun, including bootstrap and agent-specific environment exports.
- Agent modules such as `codex` and `claude-code` should stay thin. They should mostly declare package name, binary name, config directory, and any agent-specific packages or environment exports.

## Adding A New Agent

1. Decide whether the agent fits an existing shared family such as [`modules/bun-agent/`](./modules/bun-agent).
2. Add a new module directory, for example `modules/my-agent/`.
3. Create `modules/my-agent/module.nix` as a thin overlay over the shared family module.
4. Add flake wiring for:
   - `nixosModules.firebreak-my-agent`
   - `nixosConfigurations.firebreak-my-agent`
   - `packages.firebreak-my-agent`
   - `packages.firebreak-my-agent-shell`
   - `packages.firebreak-my-agent-smoke`
5. Reuse the shared smoke template unless the agent truly needs different validation behavior.

## Rules

- Do not add new top-level `scripts/` or `tests/` directories.
- Keep internal implementation files inside the module that owns them.
- Keep `flake.nix` as assembly glue, not as the place where runtime logic accumulates.
