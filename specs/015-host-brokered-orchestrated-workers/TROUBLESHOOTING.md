---
status: living
last_updated: 2026-03-28
---

# 015 Troubleshooting Playbook

This document records the operational lessons from debugging host-brokered worker spawning through Firebreak, especially the attached `codex` path reached through a parent orchestrator VM.

The goal is simple: next time a process launched from inside a VM appears stuck, use this playbook instead of re-deriving the same boundaries from scratch.

## What we were trying to make work

The target path was:

1. an orchestrator VM starts normally
2. the orchestrator invokes `firebreak worker run ...` through the guest bridge
3. the host broker launches a sibling Firebreak worker VM
4. the orchestrator receives a live attached terminal to that sibling worker
5. the sibling worker starts a packaged CLI such as `codex`
6. the user sees a real interactive session instead of a detached log dump or a hang

The key architectural decision remains:

- the orchestrator VM is a control plane
- sibling workers are host-brokered
- guest-launched nested VM spawning is not the product contract

## Durable decisions

- Keep the host-brokered sibling-worker architecture.
- Do not treat guest-launched nested virtualization as the fallback product path.
- Treat attached-worker debugging as a layered problem, not a single end-to-end black box.
- Prefer focused smokes over manual AO sessions during investigation.
- Treat AO end-to-end sessions as integration gates after lower-layer smokes are green.
- Preserve a real PTY path for interactive workers.
- Publish machine-readable lifecycle state for bootstrap and command handoff.
- Preserve reviewable bridge traces after request cleanup.
- Do not accept repeated boot-time network installs as the normal steady-state startup contract.
- Prefer deterministic packaged-tool delivery through baked or host-shared prepared tools.

## Failure modes we actually saw

These are not hypothetical. They all occurred during this slice.

### 1. Silent attach stalls

Symptoms:

- worker creation succeeded
- outer session printed `worker started, waiting for output`
- no visible nested output arrived

Root causes we uncovered:

- output was being produced but not mirrored through the bridge
- FIFO-based transport across the shared mount was unreliable
- later, request cleanup erased evidence too early

What fixed it:

- replace the `script | tee` style path with a direct PTY driver
- switch the interactive transport to append-only stream files
- persist bridge traces and exit-code evidence under the worker root

### 2. Bootstrap ambiguity

Symptoms:

- nested VM visibly booted
- startup stalled somewhere around developer-tool installation
- console logs alone were too truncated to prove which phase failed

Root causes:

- packaged bootstrap had no machine-readable contract
- success and failure were inferred from terminal fragments
- shared-tools readiness and guest session prep could race

What fixed it:

- publish `bootstrap-state.json`
- publish `command-state.json`
- surface both through `firebreak worker debug`
- make `prepare-agent-session` and `dev-bootstrap` ordering explicit

### 3. Wrong focus on transport after transport was already good

Symptoms:

- repeated end-to-end AO retries
- many changes in the relay layer even after evidence showed the nested command was already alive

What we learned:

- once the following all became true:
  - `command-start`
  - live child process
  - working stdin
  - working stdout
  - nested banner visible
- the problem had moved out of generic attach transport and into packaged startup or UX cleanup

This was the main strategic pivot.

### 4. Boot-time package installation dominating startup

Symptoms:

- most of boot time spent in `Install persistent developer tools before login`
- attached sessions paid the same install cost repeatedly

What fixed it:

- move Bun and packaged node-cli workers to a host-owned shared tools mount
- add explicit cache-hit phases such as `toolchain-cache-hit`
- treat install/repair as exceptional rather than default

### 5. Guest shell noise leaking into the user transcript

Symptoms:

- `[1] 1234` job-control line leaked into the nested session
- `/proc/.../cmdline` races leaked shell noise

What fixed it:

- quiet the guest-side monitor launch path
- avoid noisy `/proc` reads when processes disappear between probes

### 6. Debug output too noisy to read

Symptoms:

- `worker debug` printed raw OSC, DCS, cursor query, and bracketed-paste sequences
- review output was technically correct but operationally useless

What fixed it:

- sanitize control-sequence noise in debug transcript tails only
- keep the live PTY stream raw so interactive terminal behavior still works

## What worked well

- Narrow machine-readable phase files were much better than reading console fragments.
- Request-level trace logs were worth the effort.
- Preserving failed runtime directories saved time immediately.
- Synthetic interactive workers were extremely valuable.
- A no-forward recipe variant was the right way to isolate worker behavior from host port collisions.
- A host PTY harness for recipe-owned interactive smokes was much more faithful than feeding `script` from a pipe.

## What did not work well

- Using the full AO end-to-end path as the first debugger.
- Relying on terminal text alone as the source of truth.
- Accepting dynamic package install as part of normal attached-worker startup.
- Bundling too many unrelated uncertainties into one repro.
- Treating long-running interactive exec sessions as reliable evidence collectors inside every automation environment.

## Repeatable debugging order

When VM-spawned process execution looks broken, debug in this order.

### Layer 1: broker and worker lifecycle

Questions:

- did the worker get created?
- does it have a stable worker id?
- is the host-owned worker root present?

Check:

- `firebreak worker ps`
- `firebreak worker inspect <id>`

Do not move on until this layer is sound.

### Layer 2: bridge request publication

Questions:

- did the guest bridge publish a request?
- was it marked attached and interactive?
- what terminal contract was requested?

Check:

- `firebreak worker debug`
- `bridge_request_*` fields

Key fields:

- `bridge_request_id`
- `bridge_request_attach`
- `bridge_request_interactive`
- `bridge_request_term`
- `bridge_request_columns`
- `bridge_request_lines`

### Layer 3: PTY attach path

Questions:

- did the host open the attached PTY?
- did stdin and stdout streams open?
- did the first stdout byte reach the bridge?

Key signals:

- `attach-pty-open`
- `attach-stdin-stream-opened`
- `attach-stdout-stream-opened`
- `attach-stdout-first-byte`

If these are absent, the problem is transport.

### Layer 4: guest bootstrap

Questions:

- did the sibling VM reach the packaged tool bootstrap ready state?

Check:

- `guest_bootstrap_state_phase`
- `guest_bootstrap_state_status`
- `guest_bootstrap_state_detail`

Good steady-state signal:

- `phase: wrapper-ready`
- `status: ready`

If not, stop debugging PTYs. The problem is now inside guest startup.

### Layer 5: guest command handoff

Questions:

- did the actual command start?
- what exact command was launched?
- what process is alive?

Check:

- `guest_command_state_phase`
- `guest_command_state_command`
- `agent_exec_command_processes_tail`

Good signals:

- `phase: command-start`
- live packaged child process, for example `node .../codex`

### Layer 6: packaged-tool delivery

Questions:

- is startup blocked on installation?
- is the shared tools path mounted?
- is the cache-hit path being used?

Check:

- bootstrap phase logs
- `tool-home ...`
- `tool-ready-marker ...`
- `toolchain-cache-hit ...`

If cache-hit never appears on repeated runs, fix packaged-tool reuse before touching relay code.

### Layer 7: user-facing transcript quality

Questions:

- does the session work but look ugly?
- are we seeing shell-monitor noise or terminal control chatter?

At this point the problem is UX polish, not execution correctness.

## Known good signals

When the attached path is healthy, the following cluster is expected:

- `guest_bootstrap_state_phase: wrapper-ready`
- `guest_bootstrap_state_status: ready`
- `guest_command_state_phase: command-start`
- `bridge_request_last_event: nested-command-first-byte` or later
- `command-stdout-first-byte` in wrapper trace
- live packaged child process in `agent_exec_command_processes_tail`
- nested worker welcome banner visible in transcript

For recipe-owned AO coverage, the smoke only needs to prove:

- outer AO shell banner
- `firebreak: worker produced terminal output`
- nested `firebreak-codex` terminal output

It does not need to prove a long interactive session lifetime.

## Recommended validation ladder

Use this order unless there is a strong reason not to.

1. `bash -n` on touched runtime scripts
2. direct packaged-cli readiness smoke
3. focused attached Firebreak worker smoke
4. isolated synthetic interactive smoke
5. recipe-owned detached/proxy smokes
6. recipe-owned interactive smoke
7. one manual AO integration check

## Commands worth keeping

### Direct broker visibility

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  run .#firebreak -- worker debug
```

### Attached worker smoke

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  run .#firebreak-test-smoke-worker-firebreak-attach
```

### Synthetic interactive sibling-worker smoke

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  run .#firebreak-test-smoke-worker-guest-bridge-interactive
```

### Recipe-owned interactive AO smoke

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  run ./external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-interactive \
  --override-input firebreak .
```

## Anti-patterns to avoid next time

- Do not jump straight to manual AO sessions as the primary debugger.
- Do not change transport and bootstrap at the same time unless the current evidence is genuinely ambiguous.
- Do not rely on terminal screenshots as the source of truth.
- Do not accept “it probably hangs before output” without bridge traces proving it.
- Do not optimize the live PTY path by stripping control bytes unless you are prepared to risk real terminal regressions.
- Do not leave the troubleshooting contract undocumented inside only commit history.

## Current conclusion

As of the end of this slice:

- host-brokered sibling-worker spawning is viable
- attached interactive `codex` works through the AO recipe
- deterministic prepared-tools reuse is the right startup model
- the next likely improvements are UX polish and cleanup policy, not architectural rescue
