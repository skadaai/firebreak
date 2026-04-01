<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-dark.jpg">
    <source media="(prefers-color-scheme: light)" srcset="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
    <img width="280" alt="Firebreak's logo" src="https://cdn.jsdelivr.net/gh/skadaai/firebreak@main/.github/media/logo-light.jpg">
  </picture>
<p>

# Firebreak

Firebreak is a VM-first control plane for running coding agents with a small public interface.

## Firebreak CLI

```sh
firebreak vms
firebreak run codex
firebreak run codex --shell
firebreak run codex --worker-proxy-mode local
firebreak run claude-code -- --help
```

`firebreak vms` lists the public VM workloads. `firebreak run <vm>` launches one of them through the existing Firebreak VM packages.

For packaged node-cli VMs that expose `workerProxies`, `firebreak run` can also choose whether commands such as `codex` and `claude` launch as sibling Firebreak workers or as regular in-VM processes:

```sh
npx firebreak run codex --worker-proxy-mode worker
npx firebreak run codex --worker-proxy-mode local
```

The same switch is available through `FIREBREAK_WORKER_PROXY_MODE=worker|local` when you launch an external recipe package directly with `nix run`.

## Local Workloads

- `nix run .#firebreak-codex` launches Codex in the local Firebreak VM
- `nix run .#firebreak-claude-code` launches Claude Code in the local Firebreak VM
- `FIREBREAK_VM_MODE=shell nix run .#firebreak-codex` reaches the maintenance shell for the same VM package
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
AGENT_CONFIG=workspace
# FIREBREAK_VM_MODE=run
# CODEX_CONFIG=workspace
# CLAUDE_CONFIG=workspace
```

## Diagnostics

`firebreak doctor` reports:

- project root and config-file resolution
- host platform and selected local runtime path
- public VM mode resolution
- Codex and Claude Code config resolution
- current working directory compatibility
- KVM availability when relevant, plus primary-checkout state

Use `nix run .#firebreak -- doctor --json` for machine-readable output.

## Orchestrated Workers

Firebreak exposes a public `worker` surface for orchestrator-style sandboxes:

```sh
firebreak worker run --kind codex --workspace "$PWD" -- --version
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
    backend = "firebreak";
    package = "firebreak-codex";
    vm_mode = "run";
    max_instances = 4;
  };
  claude = {
    kind = "claude-code";
    backend = "firebreak";
    package = "firebreak-claude-code";
    vm_mode = "run";
    max_instances = 2;
  };
};
```

For packaged node-cli recipes, Firebreak also exposes `firebreak-bootstrap-wait` inside the guest so recipe-owned validation can wait for the shared bootstrap service to finish before probing installed CLIs or worker-proxy wrappers. Those generated proxy commands honor `FIREBREAK_WORKER_PROXY_MODE=worker|local`, so the same recipe can flip between sibling-worker routing and regular in-VM execution without redefining command names.
