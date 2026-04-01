---
status: in_progress
last_updated: 2026-04-01
---

# 015 Status

## Current phase

Interactive TUI hardening after the first full end-to-end success. The current attached relay path is now strong enough to boot sibling workers, surface nested CLI output, and drive real onboarding transitions for both `claude` and `codex` through focused smokes and manual AO/VK validation. `codex` is now a protected working path in both AO and `vibe-kanban`, and `claude` is also working interactively in those product-layer VMs. The remaining open work has narrowed to stricter shared-layer lifecycle coverage and polish rather than the basic product path.

## What has landed

- a tracked spec, plan, and status record for host-brokered orchestrated workers
- a durable decision that `firebreak` workers should be host-brokered sibling VMs rather than guest-launched nested VMs
- a first-pass backend model with `process` and `firebreak`
- a host-side broker surface under `firebreak worker` with `run`, `ps`, `inspect`, `logs`, `stop`, `rm`, and `prune`
- a first worker-state model with stable worker ids, per-worker metadata, and host-owned runtime paths
- smoke coverage for the broker lifecycle and the CLI route into `firebreak worker`
- a local-profile guest bridge that mounts a request-response share and exposes guest-visible `firebreak worker ...` forwarding inside bridge-enabled orchestrator VMs
- focused VM smoke coverage proving a guest can call the worker surface through that bridge
- guest-local `process` worker semantics through a guest-owned worker state directory and the same `firebreak worker` surface
- first worker-kind declarations in bridge-enabled VMs so a guest can resolve kinds to `process` or `firebreak` without raw backend flags
- per-kind bounded concurrency through `max_instances` in worker-kind declarations
- first recipe-level worker-kind declarations in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix)
- generic packaged-node-cli support for declarative extra bin scripts
- a generic packaged-node bootstrap-readiness helper (`firebreak-bootstrap-wait`) for recipe-owned validation and wrapper probing
- a reusable Firebreak worker-proxy script helper for external recipes that want a CLI name to resolve through `firebreak worker`
- a recipe-owned smoke path in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) for validating bootstrap readiness and worker-proxy wrapper installation without moving orchestrator logic into Firebreak core
- a recipe-owned smoke path in [external/agent-orchestrator/flake.nix](../../external/agent-orchestrator/flake.nix) for real declared-worker creation through the guest-visible `firebreak worker` surface
- the attached execution contract has been identified as the remaining weak spot inside the `firebreak` backend rather than in worker-kind declaration or detached worker lifecycle plumbing
- attached sibling-worker transport now exposes request-level bridge traces, live nested runtime traces, and streamed boot output back into the orchestrator guest
- packaged Bun-agent bootstrap now emits explicit machine-readable bootstrap phases and avoids recursive ownership fixups during startup
- `firebreak worker debug` now surfaces machine-readable guest bootstrap and command state when packaged-cli workers publish them through the exec-output mount
- direct packaged-cli readiness smokes now preserve reviewable runtime evidence long enough to assert guest lifecycle artifacts instead of relying only on terminal output
- the direct packaged-cli readiness path now waits for guest bootstrap readiness before one-shot agent commands execute, so `--version` probes no longer race bootstrap
- attached worker traces are now being hardened so request-level bridge events and response exit codes can survive request-directory cleanup, and so post-`command-start` output can be distinguished from earlier boot noise
- attached worker request metadata is now reviewable in `firebreak worker debug`, and zero or malformed terminal geometry is dropped instead of being forced onto the sibling PTY
- attached worker debugging now proves that the live nested `codex` process starts, receives a sane interactive tty contract, and can be inspected through machine-readable guest process snapshots
- the branch now records an explicit strategic pivot: keep the host-brokered sibling-worker architecture, but stop accepting boot-time dynamic package installation as the normal attached-worker startup contract
- the attached sibling-worker relay now uses a direct PTY driver instead of a `script`-piped shim, and focused traces distinguish boot output from real post-command output
- the local profile now reuses and seeds prepared packaged-tool state across worker boots through a host-owned shared tools mount
- the focused attached worker smoke now accepts either first-run install or seeded cache reuse, then still proves reuse on a later run
- an isolated interactive guest-bridge smoke now proves end-to-end `READY` and `ECHO:ping` behavior for an attached sibling worker, with preserved runtime artifacts and host debug evidence on failure
- guest session preparation now emits explicit phase breadcrumbs so long startup steps such as workspace and tools setup can be reviewed without manual VM archaeology
- packaged node-cli workers now use the same host-owned shared tools model as Bun workers, instead of paying full bootstrap cost from per-VM state on every run
- the external Agent Orchestrator smokes now validate through a no-forward test package so worker behavior tests are not blocked by unrelated host port collisions
- the external Agent Orchestrator recipe now has a focused interactive `codex` smoke that exercises the attached sibling-worker path under a host PTY instead of relying on manual AO sessions
- attached interactive `codex` through the external Agent Orchestrator recipe is now validated on the current head through the focused recipe-owned PTY smoke
- `firebreak worker debug` now sanitizes transcript-tail control chatter so operational review focuses on meaningful worker output instead of raw terminal negotiation noise
- this slice now has a dedicated troubleshooting playbook for VM-spawned process failures in [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- worker exec resolution for attached sibling workers is now explicit and reviewable through `firebreak worker debug`, so diagnosis does not depend on guessing which wrapped command actually launched
- the attached relay now handles terminal queries at the PTY edge and traces query/reply traffic distinctly from ordinary stdin delivery
- attached interactive stdin handling now normalizes ordinary activation input and filters automatic terminal replies out of the ordinary user-input stream
- focused synthetic interactive coverage now proves that an attached sibling-worker TTY can deliver meaningful input and output transitions end to end
- the external Agent Orchestrator recipe now exposes a `claude` worker proxy that launches the `claude-code` Firebreak worker kind from inside AO
- the external Agent Orchestrator recipe now has a focused interactive `claude` smoke so full-screen TUI behavior can be validated through a second packaged CLI canary rather than relying only on `codex`
- the current head can surface the Claude onboarding/theme UI through AO, which retired the architecture risk and moved the remaining risk squarely into terminal-usability behavior
- lower-latency relay polling is now part of the attached interactive path so menu navigation and first-screen interaction are no longer dominated by coarse bridge sleeps
- the direct attached `claude` smoke now proves a real post-input transition from theme selection into login selection, which means the inner worker PTY and guest tty/session semantics are no longer the dominant remaining risk
- the Agent Orchestrator interactive `claude` smoke now passes end to end, including a post-input transition past the theme screen
- attached worker lifecycle now publishes PTY-side `command-start` and `command-exit` stream markers so the host relay can observe command-state transitions immediately instead of waiting only on shared-file visibility
- the shared attached relay now escalates repeated interactive `Ctrl-C` requests through the worker signal channel, so product-layer `claude` exit behavior no longer depends solely on raw TTY byte delivery
- the current head passes focused product-layer validation for interactive `codex` in AO and `vibe-kanban`, and for interactive `claude` in AO
- manual AO validation now confirms that `claude` can be launched interactively and that `Enter` works inside the nested worker session on the current head
- manual AO validation now confirms that `claude` can advance into its login flow, while also revealing a teardown bug where exiting the nested Claude session can still hang or terminate the parent AO VM instead of returning control cleanly
- current manual AO validation for `codex` shows the nested worker starts and remains alive, and the remaining visibility bug has narrowed further from "missing basic terminal replies" to "Codex still renders blank even after richer PTY-edge replies and filtering are restored"
- current manual AO validation for `claude` shows startup and interaction work, but exiting the nested session from AO still leaves the worker hanging after the `Press Ctrl-C again to exit` prompt
- the external `vibe-kanban` recipe now exposes the same `codex` and `claude` sibling-worker proxy commands as AO, so the remaining TUI bugs can be compared against a second VM recipe canary
- packaged node-cli worker proxies now support a shared `FIREBREAK_WORKER_MODE=vm|local` switch plus per-command `FIREBREAK_WORKER_MODES=name=mode,...` overrides, and the public `firebreak run` surface can set both through `--worker-mode`
- a committed `vibe-kanban` interactive Codex smoke now protects the working Codex path against regressions while shared TUI lifecycle work continues
- the same current worktree now reproduces the `claude` exit-limbo behavior in both AO and `vibe-kanban`, which retired recipe-specific suspicion and isolated the bug in the shared attached-worker lifecycle
- a direct shared-layer `claude` exit smoke now reproduces the same raw-mode repeated-`Ctrl-C` behavior without AO or `vibe-kanban`, so the shared worker layer has a fast acceptance gate for this bug
- the shared attached-worker path now tracks a foreground command job/pgid and can distinguish a first raw `Ctrl-C` from a repeated one, which is the basis for fixing nested-TUI exit without regressing normal interactive input

## What remains open

- finish the outer-shell handback after a nested `claude` worker exits cleanly, so AO and `vibe-kanban` regain a visibly usable prompt without an extra manual nudge
- confirm that attached full-screen CLIs are responsive enough in practice, not only correct in traces
- settle the final minimum terminal contract for attached packaged CLIs, including which queries must be answered at the PTY edge and which should remain unsupported
- reduce remaining user-visible terminal-noise and layout rough edges without regressing real PTY semantics
- continue improving deterministic packaged-tool delivery so first-run startup cost is low enough for daily use
- richer lifecycle behavior such as worker reuse, log filtering, and cleanup policy refinements
- possible transport hardening beyond the first file-share bridge, such as a mounted Unix-socket protocol
- broader recipe adoption and validation beyond the first external orchestrator recipe
- stricter shared-layer lifecycle coverage for attached `claude` exit semantics, so the direct canary can match the currently working AO/VK product behavior without relying on looser integration harness timing
- optional polish for transcript noise, live-session cleanup, and any remaining debug-vs-live presentation rough edges

## Decision record

- The host-brokered sibling-worker model is still the right architecture and remains in scope.
- The investigation has already paid off enough to prove that broker creation, attach transport, terminal propagation, and nested command handoff are not the dominant remaining risks.
- The major open risk has shifted from spawn architecture to shared interactive lifecycle hardening and stricter generic coverage for packaged full-screen CLIs.
- `claude` is now treated as the clearer TUI canary for remaining terminal-contract bugs, while `codex` remains an important product target and the current regression gate.
- End-to-end AO repros are now treated as integration gates, not as the primary debug loop. Focused direct packaged-worker readiness and reuse validation should lead.
- Acceptance must now include meaningful post-input TUI behavior, not just "process started and emitted output".
- Acceptance must also include correct nested-session teardown behavior. A working nested TUI is not sufficient if exiting it kills the orchestrator VM.
- The current recipe-authoring UX is functionally correct but too low-level in the common case. Firebreak should converge on a single higher-level declaration for sibling-worker command exposure while preserving the lower-level fields internally for advanced recipes.
- Product-layer validation in both AO and `vibe-kanban` now takes precedence over stricter experimental shared-layer canaries when deciding what is mature enough to bank. The direct canaries remain important, but they should not block landing a clearly working shared runtime improvement when the user-facing paths are already green.

## Current sources of truth

- [SPEC.md](./SPEC.md)
- [PLAN.md](./PLAN.md)
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

## History

- 2026-03-24: Created this spec after deciding that orchestrated worker fan-out needs a Firebreak-native contract instead of ad hoc process spawning or guest-launched nested virtualization.
- 2026-03-24: Landed the first host-broker slice with `firebreak worker`, worker metadata, `process` and `firebreak` backend spawning, and focused smoke coverage.
- 2026-03-25: Promoted the broker surface from maintainer-only `internal` naming to the top-level public `worker` command and aligned the slice vocabulary around workers instead of agents.
- 2026-03-25: Landed the first guest-bridge slice for local orchestrator VMs with a mounted request-response channel, guest-visible `firebreak worker` forwarding, and focused bridge smoke coverage.
- 2026-03-25: Split worker execution authority cleanly so declared `process` workers are guest-local while declared `firebreak` workers stay host-brokered, and added recipe-level worker-kind declarations.
- 2026-03-25: Added generic packaged-node-cli support for declarative extra bin scripts and a reusable worker-proxy helper so external recipes can route selected CLI names through `firebreak worker` without adding orchestrator-specific code to Firebreak's shared layers.
- 2026-03-25: Added a generic packaged-node bootstrap-readiness helper, bounded per-kind concurrency via `max_instances`, and a recipe-owned validation path for the first external orchestrator recipe.
- 2026-03-26: Reworked the public worker CLI around `run`, `ps`, `inspect`, `logs`, `stop`, `rm`, and `prune`, made default listing concise, and added worker cleanup semantics.
- 2026-03-26: Confirmed the first external orchestrator recipe manually in a real runtime: guest-visible worker execution, host-owned worker state, concise listing, cleanup, and bounded concurrency all behaved as specified.
- 2026-03-26: Reopened the spec after confirming that attached sibling-worker execution for interactive `firebreak` workers is still incomplete even though detached lifecycle behavior and manual detached validation already passed.
- 2026-03-27: Added bridge-level attach diagnostics, streamed nested runner output, guest-visible attach progress, and packaged Bun-agent bootstrap phase markers so attached-worker failures can be diagnosed without raw host-side process archaeology.
- 2026-03-28: Recorded the strategic pivot explicitly. The branch will continue on the host-brokered sibling-worker architecture, but remaining work is now framed as deterministic packaged-tool delivery and reuse rather than generic attach transport debugging.
- 2026-03-28: Replaced the unstable `script`-based attached relay with a direct PTY driver, proved the focused interactive sibling-worker path with an isolated synthetic worker smoke, and kept the remaining open risk centered on deterministic prepared-tools delivery rather than relay correctness.
- 2026-03-28: Extended the shared prepared-tools model to packaged node-cli workers, moved the Agent Orchestrator recipe smokes onto a no-forward test variant, and validated both recipe-owned runtime smokes against the new path.
- 2026-03-28: Added a recipe-owned interactive Agent Orchestrator smoke for plain attached `codex`, so the AO path now has automated PTY-backed coverage beyond `--version` and detached worker lifecycle checks.
- 2026-03-28: Confirmed the current head can surface an attached interactive `codex` session through the Agent Orchestrator recipe, sanitized debug transcript tails for attached workers, and recorded the full troubleshooting playbook for future VM-spawn debugging.
- 2026-03-29: Stabilized attached interactive TUI workers in AO further by moving query handling to the PTY edge, adding stronger interactive smokes, and exposing `claude` as a second packaged CLI canary through the Agent Orchestrator recipe.
- 2026-03-30: Recorded the deeper terminal lessons from the Codex and Claude investigations. The remaining boundary is now explicitly framed as interactive usability, responsiveness, and terminal-contract polish rather than worker-spawn architecture.
- 2026-03-31: Proved a real post-input transition for direct and AO `claude` smokes, confirmed manual AO `Enter` behavior, and narrowed the open bugs to nested-TUI shutdown behavior that currently terminates the parent AO VM when `claude` exits plus a remaining Codex visibility gap where the worker starts but the UI may stay black.
- 2026-03-31: Narrowed the remaining Codex black-screen bug further by identifying an AO-bridge mismatch: the direct PTY path kept handling terminal-control flows after `command-start`, while the AO bridge path stopped at that boundary. The current fix keeps PTY-edge handling active for the full attached session.
- 2026-03-31: Restored richer PTY-edge replies for attached sessions (`CSI 6n`, DA1, kitty keyboard query, OSC 10/11, focus-in) and confirmed that Codex now receives those replies on the direct canary, but a visible auth screen is still not guaranteed. The remaining Claude bug also narrowed: AO can reach the second-exit prompt, yet the nested `claude` process can still remain alive instead of returning control cleanly.
- 2026-03-31: Exposed `codex` and `claude` through the external `vibe-kanban` recipe as a second orchestrator-style VM canary and recorded the follow-up authoring-UX decision to collapse the common recipe path into a higher-level `workerProxies` abstraction in a future slice.
- 2026-03-31: Confirmed that `codex` now works inside both AO and `vibe-kanban`, committed a `vibe-kanban` interactive Codex smoke as a regression guard, and reprioritized the remaining work around the shared `claude` exit-handback bug.
- 2026-03-31: Added a direct shared-layer `claude` exit smoke, proved that the nested worker can now exit cleanly on the repeated-interrupt path, and narrowed the remaining open issue to the outer prompt/terminal handback after the worker is already gone.
- 2026-03-31: Implemented the higher-level `workerProxies` recipe abstraction for packaged node-cli VMs, validated that it derives both worker-kind JSON and installed `codex`/`claude` proxy scripts, and migrated the AO and `vibe-kanban` recipes off duplicated `workerKinds` plus `installBinScripts` wiring.
- 2026-04-01: Landed PTY-side command stream markers and shared repeated-interrupt escalation in the attached relay, then revalidated the working product paths through AO and `vibe-kanban`. The current head now keeps interactive `codex` and `claude` working in the product-layer VMs while the remaining shared direct-exit canary is treated as a stricter follow-up gate rather than the release blocker for this slice.
