# External Project Sandboxes

This directory holds Firebreak sandbox recipes for projects that live outside this repository.

The current recipes are:

- [`agent-orchestrator`](./agent-orchestrator): VM profile for `ComposioHQ/agent-orchestrator`
- [`vibe-kanban`](./vibe-kanban): VM profile for `BloopAI/vibe-kanban`

Current forwarded host ports:

- `agent-orchestrator`: `127.0.0.1:3000`, `127.0.0.1:14800`, `127.0.0.1:14801`
- `vibe-kanban`: `127.0.0.1:3000`, `127.0.0.1:3001`

These flakes are consumer-oriented sandboxes for the published CLIs. They mount the caller's current working directory as the target workspace, but they do not require a checkout of the upstream tool's own repository.

On the first successful boot, the VM prepares the packaged CLI launcher before opening the console. In normal `run` mode, the VM then enters the tool's primary command against the mounted workspace. In `shell` mode, it drops into the prepared shell instead.

Each sandbox also exposes:

- `project-launch`: rerun the default project command from the prepared shell
- `project-ready`: print the current project-ready status and the main commands for that repo
- `firebreak-refresh-cli`: reinstall the packaged CLI on the next bootstrap cycle

Example commands:

```bash
cd ~/your-project
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run path:/path/to/firebreak/external/agent-orchestrator#firebreak-agent-orchestrator
```

```bash
cd ~/your-project
FIREBREAK_VM_MODE=shell nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
  path:./path/to/firebreak/external/agent-orchestrator \
  --override-input firebreak path:$PWD
```


```bash
cd ~/your-project
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run path:/path/to/firebreak/external/vibe-kanban#firebreak-vibe-kanban
```

To build the VM artifacts without launching them:

```bash
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' build path:/path/to/firebreak/external/agent-orchestrator#firebreak-internal-runner-agent-orchestrator
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' build path:/path/to/firebreak/external/vibe-kanban#firebreak-internal-runner-vibe-kanban
```

The nested flakes are structured so they can live in external repositories and consume a published Firebreak input.

For local development inside this repo, test the nested flake against your checkout explicitly:

```bash
cd ~/your-project
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
  path:/path/to/firebreak/external/agent-orchestrator#firebreak-agent-orchestrator \
  --override-input firebreak path:/path/to/firebreak/ao
```

If a nested external flake errors with `attribute 'lib' missing`, that means its locked `github:skadaai/firebreak` input is older than the library export available in your checkout. Override the input explicitly when testing locally, or update/publish the upstream Firebreak input first.

## Difficulties Found

1. Resolved in this change: the root Firebreak flake needed an explicit `nixpkgs` input so child flakes could depend on a stable parent contract instead of an implicit lockfile node.
2. Resolved in this change: Firebreak needed public helpers for reusable sandbox recipes. `firebreak.lib.${system}` now exposes both source-workspace and packaged-CLI builders so child flakes do not duplicate wrapper and runner packaging internals.
3. Resolved in this change: packaged CLI sandboxes like `ao` and `vibe-kanban` should not require a checkout of the upstream tool repository. They now bootstrap the published CLI directly and use the mounted `PWD` only as the target workspace.
4. Remaining friction: the local profile always mounts the caller's `PWD`. That keeps the launcher simple, but it still means the user cannot yet choose an arbitrary host workspace path independently of the launch directory.
5. Remaining friction: Firebreak still hardcodes `x86_64-linux` in the root flake. External recipes inherit the same host and guest assumption instead of deriving it from `builtins.currentSystem` or exposing supported systems cleanly.
6. Remaining friction: the local launcher rejects paths with whitespace because the runtime share injection does not support them. That is easy to trip over when sandboxing arbitrary external repos.
7. Remaining friction: external recipe flakes currently have no generated lockfiles in-tree. That keeps the repo light, but the first host-side build will need to create locks or run with `--no-write-lock-file`.
8. Remaining friction: full `nix build` validation depends on a writable Nix store or daemon socket. In constrained environments that means Firebreak recipes can be authored but not actually built, which argues for a more explicit validation story or helper command.
9. Remaining friction: local development against nested external flakes requires `--override-input firebreak path:/path/to/firebreak/ao` until the in-progress Firebreak helper changes are published and consumed by those child locks.
