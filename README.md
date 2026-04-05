<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-dark.jpg">
    <source media="(prefers-color-scheme: light)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
    <img width="280" alt="Firebreak's logo" src="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
  </picture>
<p>

# Firebreak

Firebreak is a VM-first control plane for running tools and workloads with a small public interface.

## Firebreak CLI

```sh
firebreak vms
firebreak run codex
firebreak run codex --shell
firebreak run codex --worker-mode local
firebreak run codex --worker-mode codex=vm --worker-mode claude=local
firebreak run claude-code -- --help
```

`firebreak vms` lists the public VM workloads. `firebreak run <vm>` launches one of them through the existing Firebreak VM packages.

For packaged node-cli VMs that expose `workerProxies`, `firebreak run` can also choose whether commands such as `codex` and `claude` launch as sibling Firebreak workers or as regular in-VM processes:

```sh
npx firebreak run codex --worker-mode vm
npx firebreak run codex --worker-mode local
npx firebreak run codex --worker-mode codex=vm --worker-mode claude=local
```

The same behavior is available through `FIREBREAK_WORKER_MODE=vm|local` for a global default and `FIREBREAK_WORKER_MODES=codex=vm,claude=local` for per-command overrides when you launch an external recipe package directly with `nix run`. CLI flags always take precedence.

## Local Workloads

- `nix run .#firebreak-codex` launches Codex in the local Firebreak VM
- `nix run .#firebreak-claude-code` launches Claude Code in the local Firebreak VM
- `FIREBREAK_LAUNCH_MODE=shell nix run .#firebreak-codex` reaches the maintenance shell for the same VM package
- supported local host systems: `x86_64-linux`, `aarch64-linux`, and Apple Silicon `aarch64-darwin`

## NPX Launcher

Firebreak ships a thin Node launcher so users can run the Nix-backed CLI with `npx firebreak ...`.

```sh
npx firebreak vms
npx firebreak run codex
npx firebreak doctor
npx firebreak init
```

The launcher:

- checks that the host is Linux on `x86_64` or `aarch64`, or Apple Silicon macOS on `arm64`
- checks that `nix` is installed and callable
- checks that `/dev/kvm` is usable before non-diagnostic commands on Linux hosts
- uses the local Firebreak checkout automatically when you run it inside a cloned Firebreak repo
- falls back to `github:skadaai/firebreak` when no local Firebreak checkout is present
- forwards all arguments to the existing Bash Firebreak CLI through `nix run`

## Project Defaults

`firebreak init` is interactive by default and writes a project-local `.firebreak.env` file tailored to the answers you choose. The file uses the same `KEY=VALUE` spelling as the public environment variables, and real environment variables take precedence over file values.

```sh
nix run .#firebreak -- init
nix run .#firebreak -- init --non-interactive
nix run .#firebreak -- doctor
```

Example `.firebreak.env`:

```dotenv
FIREBREAK_STATE_MODE=host
# FIREBREAK_LAUNCH_MODE=run
# CODEX_STATE_MODE=workspace
# CLAUDE_STATE_MODE=workspace
# FIREBREAK_CREDENTIAL_SLOT=default
# FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH=~/.firebreak/credentials
# CODEX_CREDENTIAL_SLOT=backup
```

## State Roots And Credential Slots

Use `FIREBREAK_STATE_MODE` and per-tool overrides such as `CODEX_STATE_MODE` and `CLAUDE_STATE_MODE` to choose the runtime state root:

- `host`: shared host-backed runtime state
- `workspace`: per-project runtime state
- `vm`: persistent VM-local runtime state
- `fresh`: empty runtime state for each launch

Credential slots are separate:

- `FIREBREAK_CREDENTIAL_SLOT`: default slot name
- `CODEX_CREDENTIAL_SLOT`, `CLAUDE_CREDENTIAL_SLOT`: per-tool overrides
- `FIREBREAK_CREDENTIAL_SLOTS_HOST_PATH`: shared host root that stores the named slots

See [guides/state-roots-and-credential-slots.md](./guides/state-roots-and-credential-slots.md) for the full model and examples.

## Diagnostics

`firebreak doctor` reports:

- project root and config-file resolution
- host platform and selected local runtime path
- public launch mode resolution
- Codex and Claude Code runtime-state resolution
- Codex and Claude Code credential-slot resolution
- current working directory compatibility
- KVM availability when relevant, plus primary-checkout state

Use `nix run .#firebreak -- doctor --json` for machine-readable output.

## Orchestrated Workers

Firebreak exposes a public `worker` surface for orchestrator-style sandboxes:

```sh
firebreak worker run --backend firebreak --package firebreak-codex --kind codex --workspace "$PWD" -- codex --version
firebreak worker ps
firebreak worker inspect codex-1234abcd
firebreak worker debug --json
firebreak worker stop codex-1234abcd
firebreak worker rm codex-1234abcd
```

Bridge-enabled packaged node-cli recipes can declare `workerProxies` so selected command names resolve through the shared Firebreak worker bridge by default.

Example external recipe fragment:

```nix
workerProxies = {
  codex = {
    kind = "codex";
    defaultMode = "vm";
    backend = "firebreak";
    package = "firebreak-codex";
    launch_mode = "run";
    max_instances = 4;
  };
  claude = {
    kind = "claude-code";
    defaultMode = "vm";
    backend = "firebreak";
    package = "firebreak-claude-code";
    launch_mode = "run";
    max_instances = 2;
  };
};
```

If a proxy does not define `defaultMode`, Firebreak falls back to the recipe-level `defaultWorkerMode`, which defaults to `local`.

For Firebreak-managed worker packages such as `firebreak-codex` and `firebreak-claude-code`, local mode is derived from the declared `package` automatically. Recipe authors do not need to re-declare the upstream npm package or bin name just to make `local` mode work.

For packaged node-cli recipes, Firebreak also exposes `firebreak-bootstrap-wait` inside the guest so recipe-owned validation can wait for the shared bootstrap service to finish before probing installed CLIs or worker-proxy wrappers. Those generated proxy commands honor `FIREBREAK_WORKER_MODE=vm|local` and `FIREBREAK_WORKER_MODES=command=mode,...`, so the same recipe can flip between sibling-worker routing and regular in-VM execution without redefining command names.
