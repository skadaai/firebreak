# Architecture

Firebreak uses a module-oriented layout instead of flat `scripts/` and `tests/` buckets.

## Terminology

- `task`: an isolated host-side work attempt with its own worktree, runtime state, artifacts, and metadata
- `agent session`: an interactive or non-interactive agent process context launched inside a VM
- `conversation thread`: an agent-specific memory or history object, when the agent exposes one

Do not use bare `session` to mean the host-side work unit.

## Structure

- [`modules/base/`](./modules/base): shared Firebreak VM runtime.
  - [`module.nix`](./modules/base/module.nix): common guest and VM behavior shared by local and future cloud profiles.
  - [`guest/`](./modules/base/guest): guest-side shell helpers shared across profiles.
  - [`tests/`](./modules/base/tests): generic smoke templates owned by the shared runtime.
- [`modules/profiles/local/`](./modules/profiles/local): local-launch profile.
  - [`module.nix`](./modules/profiles/local/module.nix): local-only guest and launch behavior layered over the shared runtime.
  - [`host/`](./modules/profiles/local/host): local host-side wrapper and runtime argument helpers.
  - [`guest/`](./modules/profiles/local/guest): local guest-side boot, task-preparation, and console helpers.
- [`modules/profiles/cloud/`](./modules/profiles/cloud): cloud execution profile.
  - [`module.nix`](./modules/profiles/cloud/module.nix): cloud guest behavior layered over the shared runtime.
  - [`host/`](./modules/profiles/cloud/host): cloud host-side runtime argument helpers.
  - [`guest/`](./modules/profiles/cloud/guest): cloud guest-side task preparation and job execution helpers.
- [`modules/bun-agent/`](./modules/bun-agent): shared implementation for Bun-managed agent CLIs.
  - [`module.nix`](./modules/bun-agent/module.nix): common Bun-agent overlay logic.
  - [`guest/`](./modules/bun-agent/guest): guest bootstrap and shell-init templates for Bun-backed agents.
- [`modules/codex/`](./modules/codex): Codex-specific overlay.
- [`modules/claude-code/`](./modules/claude-code): Claude Code-specific overlay.

## Separation Of Concerns

- `modules/base` owns the shared guest runtime, common VM settings, reusable shell behavior, and generic smoke validation.
- `modules/profiles/local` owns local-only launch behavior such as dynamic host cwd sharing, host identity adoption, task preparation, and the interactive console.
- `modules/profiles/cloud` owns cloud-only guest behavior such as fixed workspace semantics, prompt-driven agent execution, and non-interactive job completion.
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
