---
status: living
last_updated: 2026-04-01
---

# 015 Troubleshooting Playbook

This document records the operational lessons from debugging host-brokered worker spawning through Firebreak, especially the attached `codex` and `claude` paths reached through a parent orchestrator VM.

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

## Terminal lessons worth preserving

These lessons were expensive to learn and should be reused directly next time.

- Visible output is not the same thing as a usable TUI. We had several phases where the nested CLI clearly started, emitted terminal bytes, and still was not actually usable because terminal negotiation or input semantics were wrong.
- A worker stdin stream can contain both real user intent and automatic terminal-emulator replies. Cursor-position reports such as `ESC[17;115R` and `ESC[51;114R` are not user keystrokes and should not be allowed to leak through the same path as ordinary typing.
- Terminal mode is multidimensional. Echo, canonical buffering, raw mode, foreground process-group ownership, and feature negotiation are separate concerns. Flipping one knob can easily fix one symptom while breaking another.
- PTY-edge handling cannot stop at handoff. If the direct attached path continues filtering and replying to terminal control flows after `command-start`, then the AO bridge path must do the same. Disabling PTY-edge handling exactly when the nested command takes over is enough to leave a healthy TUI process visually blank.
- File-backed PTY relays are sensitive to polling cadence. Interactive TUIs can feel broken or sluggish even when they are technically correct if relay polling is too coarse.
- Synthetic interactive workers are mandatory. The `interactive-echo` worker made it possible to determine whether the terminal path itself was broken before involving a heavyweight CLI.
- Different CLIs make good canaries for different failure classes. `codex` was useful for proving startup and attached-output visibility, while `claude` surfaced terminal-negotiation bugs more clearly because it rendered a visible onboarding menu that reacted to arrow keys but exposed remaining activation issues.
- Full-screen TUIs are part of the product contract now. If Firebreak claims attached interactive packaged workers are supported, then cursor queries, focus tracking, alternate-screen behavior, and basic tty readiness are no longer optional debugging trivia.
- A second canary stays useful even after the first one works. `claude` reaching a usable onboarding flow through AO did not automatically imply that `codex` would also render a visible first screen on the same worktree.

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

### 7. Terminal replies leaking back as user input

Symptoms:

- a nested TUI visibly started but rendered in the wrong place
- arrow-key or onboarding menus partly worked and partly did not
- traces showed stdin chunks shaped like terminal replies rather than human keystrokes

Root causes:

- automatic terminal replies such as cursor-position reports were being forwarded through the ordinary attached stdin path
- test harnesses and bridge code both tried to emulate terminal behavior, which made the input contract harder to reason about

What fixed it:

- make the host PTY edge the authoritative place for terminal-query handling
- trace terminal replies distinctly from normal stdin
- filter automatic terminal replies out of the ordinary stdin stream before they reach the nested command

### 8. Startup proof was weaker than usability proof

Symptoms:

- the smoke proved `nested-command-first-byte`
- the nested CLI banner or onboarding screen became visible
- the session still was not actually usable

What we learned:

- proving startup is necessary but not sufficient
- for terminal apps, focused acceptance needs at least one meaningful post-input state transition, not just "a process started and emitted bytes"

This is why `claude` became the better canary late in the slice: it gave a visible onboarding menu that made incorrect terminal behavior obvious.

### 9. Inner worker green, outer orchestrator still wrong

Symptoms:

- the same packaged CLI behaved differently as a direct attached worker and from inside AO
- the direct worker path proved a real post-input transition
- the AO path still looked slower, misplaced, or non-interactive

What we learned:

- once the direct attached worker smoke passes, the guest worker tty/session setup is no longer the primary suspect
- at that point the remaining live surface is:
  - the outer host bridge
  - the AO-side attach client
  - the interaction between those two layers

This split mattered. It stopped us from continuing to churn the inner worker VM after the direct `claude` canary had already shown that `Enter` and onboarding progression worked there.

### 10. Nested TUI exit can still kill the parent orchestrator VM

Symptoms:

- `claude` started correctly from inside AO
- onboarding and login selection rendered correctly
- exiting the nested TUI from AO either terminated the whole AO VM or left it hanging instead of returning control cleanly

What this means:

- startup and interaction can be correct while teardown semantics are still wrong
- signal ownership and nested-session shutdown are part of the terminal contract
- the parent orchestrator VM must survive nested worker exit unless the user explicitly exits the orchestrator itself, and it must regain a usable prompt instead of hanging after the nested session is gone

### 13. Inner worker exit can be fixed while outer prompt handback is still wrong

Symptoms:

- the nested worker reaches `command-exit:0`
- the host bridge reaches `attach-worker-exit:0` and `response-written`
- the guest attach client reaches `guest-attach-client-main-loop-exit`
- the user still does not immediately see a usable prompt back in the parent shell

What this means:

- the remaining bug is no longer "worker did not exit"
- it is now terminal handback or prompt-visibility behavior in the parent shell after a clean attach completion
- this is a different problem class from the earlier `claude` limbo, where the nested CLI itself was still alive

What to do next:

- inspect the request-level trace for all three boundaries:
  - `attach-worker-exit`
  - `response-written`
  - `guest-attach-client-main-loop-exit`
- if all three are present, stop debugging worker teardown and focus on guest attach-client tty restoration and visible prompt handback
- prefer a direct shared-layer exit smoke for this work before using AO or other recipe VMs as confirmation layers

### 11. One TUI can work while another still renders black

Symptoms:

- `claude` starts through AO, renders a first screen, and accepts `Enter`
- `codex` starts through the same worker path and remains alive
- `worker debug` shows `command-start`, a live child process, and post-command terminal traffic
- the user still sees a black or effectively empty screen for `codex`

What this means:

- the generic worker architecture is good enough
- the remaining bug is deeper in terminal screen semantics than simple worker spawn or stdin delivery
- a live attached process is still not the same thing as a visible usable UI

What to do next:

- inspect preserved PTY traces after `command-start`
- compare direct-worker and AO-worker behavior for the same CLI
- look specifically for mode toggles, screen-clearing behavior, synchronized-output usage, and other control flows that may leave a terminal visually blank even while the process is healthy
- confirm whether basic terminal replies have already been restored before assuming the next gap is "missing CPR" or "missing DA1"

### 12. Terminal filtering can regress differently in direct and bridged paths

Symptoms:

- a direct attached worker can still show the expected UI
- the same packaged CLI through AO reaches `command-start` and stays alive
- the AO transcript stays black or nearly blank even though post-command terminal traffic is visible

Root cause we uncovered:

- the direct PTY path kept applying terminal-query handling and synchronized-output filtering after the nested command started
- the AO bridge path stopped doing that once it considered terminal emulation to have been handed off to the nested command
- this mismatch let advanced control flows such as synchronized-output mode reach AO unfiltered, which was enough to blank the visible session even while the nested CLI stayed healthy

What fixed it:

- keep the PTY edge authoritative for terminal filtering and terminal-query replies for the full attached session, not just the pre-command phase
- treat `command-start` as a stream boundary for state tracking, not as permission to stop handling terminal-control sequences

### 13. Richer terminal replies may still not be sufficient for every TUI

Symptoms:

- traces show the nested CLI receiving CPR, DA1, kitty-keyboard, OSC color, and focus replies
- the process stays alive
- the screen still stays black or effectively blank

What this means:

- the remaining bug is no longer "we forgot to answer the obvious terminal queries"
- once those replies are present, the next boundary moves to deeper rendering semantics or a different control-flow assumption inside the client
- at that point, keep instrumenting what the app emits after the replies rather than repeatedly re-adding the same reply handlers

This became the current Codex boundary late in the slice: richer generic replies were necessary, but they were not by themselves sufficient to guarantee a visible auth screen.

### 14. Nested TUI exit prompts can still hang after the second control byte

Symptoms:

- the app reaches a shutdown confirmation prompt such as `Press Ctrl-C again to exit`
- the second `Ctrl-C` byte reaches the nested worker
- the nested process remains alive in `do_epoll_wait`
- the parent orchestrator VM does not recover cleanly and may either hang or terminate unexpectedly

What this means:

- the remaining failure is not "the second key never arrived"
- startup, rendering, and ordinary interaction can all be correct while final teardown semantics are still wrong
- once this happens, the next boundary is deeper tty/signal semantics in the outer attach path, not basic stdin delivery

### 15. Declared worker proxies can still fail in `local` mode if upstream installation is treated as incidental

Symptoms:

- a packaged CLI recipe declares `workerProxies` for commands such as `codex` or `claude`
- switching the proxy to `--worker-mode local` fails with `missing upstream binary for .../.firebreak-upstream-*`
- the same command still works in `vm` mode

Root cause we uncovered:

- the wrapper contract assumed the original packaged CLI binary already existed and could simply be renamed to `.firebreak-upstream-*`
- packaged node-cli recipes only installed their primary package by default, so proxy-local commands that came from a different Firebreak worker package were never installed in the guest at all

What fixed it:

- treat the declared Firebreak worker `package = "firebreak-*"` as the source of truth for local upstream installation too
- derive the in-VM upstream package/bin install contract from that package in shared packaged-node-cli logic
- keep external recipe flakes free of duplicate npm package/bin metadata just to make `local` mode work

## What worked well

- Narrow machine-readable phase files were much better than reading console fragments.
- Request-level trace logs were worth the effort.
- Preserving failed runtime directories saved time immediately.
- Synthetic interactive workers were extremely valuable.
- A no-forward recipe variant was the right way to isolate worker behavior from host port collisions.
- A host PTY harness for recipe-owned interactive smokes was much more faithful than feeding `script` from a pipe.
- Splitting terminal-query handling from ordinary stdin handling made the remaining bugs much easier to reason about.
- Using more than one packaged CLI as a canary prevented us from overfitting all conclusions to `codex`.
- Using a direct attached-worker canary and an AO-level canary together made it possible to isolate whether a remaining bug belonged to the inner worker VM or the outer orchestrator relay.
- Keeping `launch_mode` and `worker-mode` separate avoided a misleading mental model. One controls how the VM starts; the other controls how a proxied command dispatches inside that already-started VM.

## What did not work well

- Using the full AO end-to-end path as the first debugger.
- Relying on terminal text alone as the source of truth.
- Accepting dynamic package install as part of normal attached-worker startup.
- Bundling too many unrelated uncertainties into one repro.
- Treating long-running interactive exec sessions as reliable evidence collectors inside every automation environment.
- Assuming that "output visible" implied "terminal contract correct".
- Letting test-only terminal emulation drift away from the real product relay behavior.
- Making `local` worker mode depend on undeclared incidental upstream binaries. If a proxy is part of the supported recipe contract, then its `local` mode must be provisioned deliberately, not assumed.

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

### Layer 3.5: direct attached TUI canary

Questions:

- does the packaged CLI advance after a real post-input action when launched as a direct attached worker?
- is the guest worker tty/session already good before AO is involved?

Check:

- `firebreak-test-smoke-worker-interactive-codex-direct`
- `firebreak-test-smoke-worker-interactive-claude-direct`

If the direct canary passes and AO still fails, stop editing the inner worker VM and move outward to the bridge and orchestrator attach client.

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

### Layer 5.5: terminal-contract sanity

Questions:

- is the nested CLI using the tty as a real TUI rather than as a plain stdout sink?
- are terminal-emulator replies being answered at the PTY edge instead of leaking through stdin?
- are focus tracking, cursor queries, and simple device queries being handled once rather than multiple times?

Check:

- `bridge_request_trace_tail`
- stdin byte samples and normalization traces
- live process tty ownership and file-descriptor targets in `agent_exec_command_processes_tail`

Good signals:

- `attach-stdin-first-byte` followed by human-sized input samples
- terminal-reply-specific trace events rather than CPR bytes appearing as ordinary user input
- live packaged child `fd0`, `fd1`, and `fd2` all on the guest tty

If this layer is wrong, the session may look half-alive: startup banners appear, but menus are misplaced, sluggish, or non-interactive.

### Layer 5.6: post-input transition

Questions:

- does the nested CLI only start, or does it actually react correctly to one meaningful action?
- is the remaining bug in startup, interaction, or teardown?

Check:

- Codex auth screen appears
- Claude theme picker advances into login selection

This was the layer that retired the “Claude startup only” uncertainty. Once both the direct and AO `claude` smokes advanced past the theme picker, the remaining open bug moved to nested-session teardown.

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

For full-screen packaged CLIs, the stronger healthy cluster is:

- terminal query replies are traced distinctly from user input
- no repeated CPR reply bytes appear as ordinary stdin samples
- at least one meaningful post-input UI change is observable
- the session remains readable without relying on debug-tail sanitization

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
7. recipe-owned interactive usability smoke that proves a post-input state transition
8. one manual AO integration check

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

### Recipe-owned interactive AO smoke for Claude

```sh
nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  run ./external/agent-orchestrator#firebreak-test-smoke-agent-orchestrator-worker-interactive-claude \
  --override-input firebreak .
```

## Anti-patterns to avoid next time

- Do not jump straight to manual AO sessions as the primary debugger.
- Do not change transport and bootstrap at the same time unless the current evidence is genuinely ambiguous.
- Do not rely on terminal screenshots as the source of truth.
- Do not accept “it probably hangs before output” without bridge traces proving it.
- Do not optimize the live PTY path by stripping control bytes unless you are prepared to risk real terminal regressions.
- Do not leave the troubleshooting contract undocumented inside only commit history.
- Do not treat automatic terminal replies as if they were user keystrokes.
- Do not declare success for a terminal app until at least one post-input state transition is proven.
- Do not keep editing the inner worker VM once a direct attached canary has already passed.
- Do not declare success for nested TUIs if exiting them still kills the parent orchestrator VM.

## Current conclusion

As of the end of this slice:

- host-brokered sibling-worker spawning is viable
- attached interactive `claude` now works through both the direct worker path and the AO recipe and remains the better canary for remaining terminal lifecycle work
- `codex` still needs a reliable visible first screen on the current worktree
- deterministic prepared-tools reuse is the right startup model
- the remaining hard problems are Codex visibility, terminal-contract polish, responsiveness, and nested-session teardown semantics, not architectural rescue

## Terminal contract we ended up needing

For attached sibling-worker TUIs, the minimum viable contract is now understood to include:

- a real PTY path end to end
- well-formed `TERM`, `LINES`, and `COLUMNS`
- machine-readable bootstrap and command lifecycle state
- PTY-edge handling for at least:
  - cursor-position query / CPR
  - basic device query
  - the terminal features actually emitted by the current target CLI set
- filtering of automatic terminal replies out of ordinary stdin delivery
- low-latency relay polling so selection movement feels responsive
- preserved runtime evidence on failure

## Current open boundary

The remaining product boundary is no longer "can Firebreak spawn and attach a sibling worker VM?" That has been proven.

The remaining boundary is:

- can a full-screen packaged CLI inside that worker behave like a normal interactive terminal app from the parent orchestrator's perspective?
- can that nested CLI also exit cleanly without terminating the parent orchestrator VM?

That should remain the framing for the next debugging loop.
