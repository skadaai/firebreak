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
FIREBREAK_LAUNCH_MODE=shell nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
  path:/path/to/firebreak/external/agent-orchestrator
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

The nested flakes consume the parent Firebreak checkout directly when run from this repository.

If you copy one of these recipe flakes into another repository, switch its `firebreak` input back to a published source first.

For local development inside this repo, test the nested flake directly:

```bash
cd ~/your-project
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run \
  path:/path/to/firebreak/external/agent-orchestrator#firebreak-agent-orchestrator
```

If a copied-out recipe flake errors with `attribute 'lib' missing` or `attribute 'recipeLib' missing`, point its `firebreak` input at a Firebreak revision that exports those helpers.

## Difficulties Found

1. Resolved in this change: the root Firebreak flake needed an explicit `nixpkgs` input so child flakes could depend on a stable parent contract instead of an implicit lockfile node.
2. Resolved in this change: Firebreak needed public helpers for reusable sandbox recipes. `firebreak.lib.${system}` now exposes both source-workspace and packaged-CLI builders so child flakes do not duplicate wrapper and runner packaging internals.
3. Resolved in this change: packaged CLI sandboxes like `ao` and `vibe-kanban` should not require a checkout of the upstream tool repository. They now bootstrap the published CLI directly and use the mounted `PWD` only as the target workspace.
4. Remaining friction: the local profile always mounts the caller's `PWD`. That keeps the launcher simple, but it still means the user cannot yet choose an arbitrary host workspace path independently of the launch directory.
5. Remaining friction: Firebreak still hardcodes `x86_64-linux` in the root flake. External recipes inherit the same host and guest assumption instead of deriving it from `builtins.currentSystem` or exposing supported systems cleanly.
6. Remaining friction: the local launcher rejects paths with whitespace because the runtime share injection does not support them. That is easy to trip over when sandboxing arbitrary external repos.
7. Resolved in this change: external recipe flakes now keep lockfiles in-tree so `flake check` and `nix run` do not need to mutate the working tree before the first local run.
8. Remaining friction: full `nix build` validation depends on a writable Nix store or daemon socket. In constrained environments that means Firebreak recipes can be authored but not actually built, which argues for a more explicit validation story or helper command.
9. Resolved in this change: nested external flakes now consume the in-repo Firebreak checkout directly, so local development no longer needs `--override-input firebreak ...`.
