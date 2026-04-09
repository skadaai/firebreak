# Usage Reference

## Running a test

The examples below are generic. Adapt the test attribute and any flake app
names to the current repository.

Skill-local script paths are resolved relative to this skill directory, so use
the full skill-relative path when invoking them manually from the repository root.

```bash
# Generic specific Nix check attribute example
bash .agents/skills/remote-execution/scripts/run-remote-test.sh checks.x86_64-linux.some-vm-test

## Running an arbitrary command

Pass a single shell snippet. Quote it so it reaches the helper as one argument.

```bash
bash .agents/skills/remote-execution/scripts/run-remote-command.sh \
  'pwd && nix --version'
```

## Via Nix flake apps

These are example wrapper app names only. Not every repository exposes them.

```bash
nix run .#test
nix run .#test -- checks.x86_64-linux.some-vm-test
nix run .#warm-cache
```

## Warming the Nix cache (first use only)

The first run installs Nix onto the cache volume (~60s extra).
All subsequent runs detect the cached Nix binary and skip the install (<5s).

```bash
bash .agents/skills/remote-execution/scripts/ensure-nix-cache.sh
```

Each helper writes:
- `execution.txt`: streamed stdout/stderr from the main remote execution
- `infra.log`: instance creation, bootstrap, upload, and teardown logs
- `summary.txt`: final status, phase, exit code, and saved log paths

## Test attribute naming convention

Nix check attributes live under `checks.<system>.<name>` in the flake.
For NixOS VM tests, the system is typically `x86_64-linux`.

Examples:
- `checks.x86_64-linux.some-vm-test`
- `checks.x86_64-linux.some-smoke-test`
- `checks.x86_64-linux.some-kvm-test`

To list all available check attributes in the current flake:

```bash
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake show 2>/dev/null | grep checks
```
