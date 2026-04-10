# Architecture

Firebreak uses a module-oriented layout instead of flat `scripts/` and `tests/` buckets.

## Terminology

The canonical glossary lives in [engineering/TERMINOLOGY.md](./engineering/TERMINOLOGY.md).
Use that file when terminology in other docs is unclear.

- `attempt`: one bounded change attempt with its own plan, validation evidence, review artifacts, and disposition
- `workspace`: an isolated host-side checkout and state root used for one spec line or other logically related sequence of work
- `tool`: the actual program inside the VM, such as `codex`, `claude`, `aider`, `python`, or `bash`
- `package`: a build artifact or installable unit
- `workload`: a runnable Firebreak execution definition, often backed by one or more packages
- `worker`: a running execution instance managed by the broker
- `tool session`: an interactive or non-interactive tool process context launched inside a VM when that distinction matters
- `conversation thread`: a tool-specific memory or history object, when the tool exposes one

Do not use bare `session` to mean either the workspace or the attempt.
Do not use `agent` as a new generic architectural term in Firebreak core.
Do not use `worker` to mean `tool` or `workload`.
Do not use `workload` to mean `package`.
Do not use `config` when the concept is really persistent runtime state.

## Development-Flow Surface

- [`.agents/skills/dev-flow-autonomous-flow/`](./.agents/skills/dev-flow-autonomous-flow): top-level orchestration skill for non-trivial autonomous work.
- [`.agents/skills/dev-flow-spec-driving/`](./.agents/skills/dev-flow-spec-driving): identifies the owning spec and next independent slice.
- [`.agents/skills/dev-flow-workspace/`](./.agents/skills/dev-flow-workspace): decides whether to reuse the current workspace or create another one.
- [`.agents/skills/dev-flow-validation/`](./.agents/skills/dev-flow-validation): records machine-readable validation evidence.
- [`.agents/profiles/`](./.agents/profiles): role and runtime overlays that compose those skills into planner, worker, reviewer, validator, and runtime-specific operating modes.
- [`.agents/profiles/ROLE_SELECTION.md`](./.agents/profiles/ROLE_SELECTION.md): preconditions and authority boundaries for choosing the right role.

## Structure

- [`flake.nix`](./flake.nix): flake inputs and top-level output assembly.
- [`nix/`](./nix): flake support and focused output assembly.
  - [`flake-support.nix`](./nix/flake-support.nix): thin composition layer for shared flake helpers.
  - [`support/`](./nix/support): focused helper families for runtime assembly, project recipes, and package builders.
  - [`outputs/`](./nix/outputs): focused output attrsets for modules, configurations, packages, and checks.
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
- [`modules/packaged-agent/`](./modules/packaged-agent): legacy path name for shared implementation of image-baked tool CLIs.
  - [`module.nix`](./modules/packaged-agent/module.nix): common overlay logic for those packaged tools.
  - [`guest/`](./modules/packaged-agent/guest): guest shell-init templates for packaged tools.
- [`modules/node-cli/`](./modules/node-cli): shared implementation for npm-installed Node CLI sandboxes.
  - [`module.nix`](./modules/node-cli/module.nix): common Node CLI overlay logic.
  - [`guest/`](./modules/node-cli/guest): guest bootstrap and shell-init templates for packaged Node CLIs.
- [`modules/codex/`](./modules/codex): Codex-specific overlay.
- [`modules/claude-code/`](./modules/claude-code): Claude Code-specific overlay.

## Separation Of Concerns

- Firebreak runtime evolution should be understood in three layers:
  - boot base: kernel, initrd, service graph, and Firebreak-owned guest/runtime semantics
  - environment overlay: package-declared and project-declared dependencies resolved by Firebreak
  - state layer: shared auth, tool state, caches, and workspace mounts
- package or project customization should extend the environment layer, not redefine the Firebreak boot base.
- `modules/base` owns the shared guest runtime, common VM settings, reusable shell behavior, and generic smoke validation.
- `modules/profiles/local` owns local-only launch behavior such as dynamic host cwd sharing, host identity adoption, task preparation, and the interactive console.
- `modules/profiles/cloud` owns cloud-only guest behavior such as fixed workspace semantics, prompt-driven tool execution, and non-interactive job completion.
- `modules/packaged-agent` owns the shared contract for tools baked into the VM image, including state-root resolution and tool-specific environment exports.
- `modules/node-cli` owns the shared contract for npm-installed packaged CLIs, including bootstrap, persistent install state, and project launch helpers.
- `modules/node-cli` also owns the generic packaged-node bootstrap readiness contract (`firebreak-bootstrap-wait`) and declarative extra wrapper installation for recipe-owned CLI aliases such as worker proxies.
- on the local Cloud Hypervisor path, packaged Node CLI delivery should prefer host-seeded shared tool runtimes over guest-time installation on the interactive shell critical path.
- `firebreak-bootstrap-wait` is a readiness gate, not the installer itself. It validates that the prepared tool runtime is ready and should stay compatible with both host-seeded and guest-fallback bootstrap paths.
- Tool-specific workload modules such as `codex` and `claude-code` should stay thin. They should mostly declare package name, binary name, state directory, and any tool-specific packages or environment exports.

## External Orchestrator Recipes

External recipes should stay declarative and thin.

- Declare orchestrated worker kinds through `workerKinds` on the recipe helper.
- Use `max_instances` on a kind when the recipe needs a bounded concurrency contract.
- Install recipe-visible wrapper binaries through `installBinScripts` instead of patching shared Firebreak code.
- Reuse `firebreak.lib.${system}.mkWorkerProxyScript` when a CLI name should resolve through `firebreak worker`.
- Keep orchestrator-specific smoke tests under the external recipe itself rather than adding them to Firebreak core.
- Treat nested `firebreak worker run ...` paths as potentially long-running even for simple commands like `--version`, because the first response can be delayed by host-side `nix build` or substitution work.

## Adding A New Tool Workload

1. Decide whether the workload fits an existing shared family such as [`modules/packaged-agent/`](./modules/packaged-agent).
2. Add a new module directory, for example `modules/my-tool/`.
3. Create `modules/my-tool/module.nix` as a thin overlay over the shared family module.
4. Add flake wiring for:
   - `nixosModules.firebreak-my-tool`
   - `nixosConfigurations.firebreak-my-tool`
   - `packages.firebreak-my-tool`
   - `packages.firebreak-test-smoke-my-tool`
5. Reuse the shared smoke template unless the workload truly needs different validation behavior.

## Rules

- Do not add new top-level `scripts/` or `tests/` directories.
- Keep internal implementation files inside the module that owns them.
- Keep `flake.nix` as assembly glue, not as the place where runtime logic accumulates.
- Keep flake implementation helpers and focused output assembly under `nix/`.
