#!/usr/bin/env bash
set -eu

choose_tmp_root() {
  if [ -n "${FIREBREAK_TEST_TMPDIR:-}" ]; then
    printf '%s\n' "$FIREBREAK_TEST_TMPDIR"
    return
  fi

  for candidate in \
    "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/firebreak-test/tmp" \
    "/cache/firebreak/firebreak/tmp" \
    "/tmp/firebreak/tmp"
  do
    if mkdir -p "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf '%s\n' "/tmp"
}

firebreak_tmp_root=$(choose_tmp_root)
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-agent-orchestrator-worker-interactive-claude-exit.XXXXXX")
status=0

cleanup() {
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    printf '%s\n' "preserved interactive AO Claude exit smoke artifacts: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}

session_log=$smoke_tmp_dir/session.log
normalized_log=$smoke_tmp_dir/session.normalized.log
worker_state_dir=$smoke_tmp_dir/worker-state
mkdir -p "$worker_state_dir"

print_failure_debug() {
  printf '%s\n' '--- host worker debug --json ---' >&2
  FIREBREAK_WORKER_STATE_DIR="$worker_state_dir" @FIREBREAK_BIN@ worker debug --json >&2 || true
}

on_exit() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -ne 0 ]; then
    print_failure_debug
  fi
  cleanup
}

trap on_exit EXIT INT TERM

AGENT_ORCHESTRATOR_BIN=@AGENT_ORCHESTRATOR_BIN@ \
SESSION_LOG="$session_log" \
NORMALIZED_LOG="$normalized_log" \
WORKER_STATE_DIR="$worker_state_dir" \
python3 - <<'PY'
import os
import pty
import re
import select
import subprocess
import sys
import time
import fcntl
import struct
import termios
import errno

bin_path = os.environ["AGENT_ORCHESTRATOR_BIN"]
log_path = os.environ["SESSION_LOG"]
normalized_log_path = os.environ["NORMALIZED_LOG"]

env = os.environ.copy()
env["FIREBREAK_INSTANCE_EPHEMERAL"] = "1"
env["FIREBREAK_LAUNCH_MODE"] = "shell"
env["FIREBREAK_WORKER_STATE_DIR"] = os.environ["WORKER_STATE_DIR"]

master_fd, slave_fd = pty.openpty()
rows = 51
cols = 114
winsize = struct.pack("HHHH", rows, cols, 0, 0)
fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

with open(log_path, "wb") as log_file, open(normalized_log_path, "w", encoding="utf-8") as normalized_log_file:
    proc = subprocess.Popen(
        [bin_path],
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        env=env,
        close_fds=True,
    )
    os.close(slave_fd)

    outer_marker = "[ vm: firebreak-agent-orchestrator | mode: shell | workspace:"
    shell_prompt_marker = "[dev@firebreak-agent-orchestrator:"
    worker_output_marker = "firebreak: worker produced terminal output"
    claude_ui_marker = "MonokaiExtended"
    claude_login_markers = [
        "/login",
        "Claude Pro",
        "Anthropic Console",
        "Amazon Bedrock",
        "Google Vertex AI",
        "Microsoft Foundry",
    ]
    control_sequence_pattern = re.compile(
        r"\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)|P.*?\x1b\\|[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])",
        re.DOTALL,
    )
    control_char_pattern = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")

    def normalize(data: bytes) -> str:
        text = data.decode("utf-8", "ignore").replace("\r", "\n")
        text = control_sequence_pattern.sub("", text)
        text = control_char_pattern.sub("", text)
        text = re.sub(r"\n+", "\n", text)
        return text

    def compact(text: str) -> str:
        return re.sub(r"\s+", "", text).lower()

    claude_exit_confirm_marker = "Press Ctrl-C again to exit"
    claude_exit_confirm_compact = compact(claude_exit_confirm_marker)

    transcript = bytearray()
    sent_claude = False
    sent_enter = False
    sent_first_interrupt = False
    sent_second_interrupt = False
    sent_third_interrupt = False
    saw_worker_output = False
    saw_claude_ui = False
    saw_claude_login = False
    saw_exit_confirm = False
    saw_shell_return = False
    enter_deadline = None
    first_interrupt_deadline = None
    second_interrupt_deadline = None
    third_interrupt_deadline = None
    deadline = time.time() + 600
    last_normalized = ""
    shell_return_baseline = 0
    compact_markers = [compact(marker) for marker in claude_login_markers]

    try:
        while time.time() < deadline:
            timeout = 0.5
            for candidate in (
                enter_deadline,
                first_interrupt_deadline,
                second_interrupt_deadline,
                third_interrupt_deadline,
            ):
                if candidate is not None:
                    timeout = max(0.0, min(timeout, candidate - time.time()))

            readable, _, _ = select.select([master_fd], [], [], timeout)
            if readable:
                try:
                    chunk = os.read(master_fd, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                transcript.extend(chunk)
                log_file.write(chunk)
                log_file.flush()
                normalized = normalize(transcript)
                if normalized != last_normalized:
                    normalized_log_file.seek(0)
                    normalized_log_file.write(normalized)
                    normalized_log_file.truncate()
                    normalized_log_file.flush()
                    last_normalized = normalized
                compact_normalized = compact(normalized)
                post_exit_normalized = normalized[shell_return_baseline:]

                if not sent_claude and outer_marker in normalized:
                    os.write(master_fd, b"claude\r")
                    sent_claude = True
                    deadline = max(deadline, time.time() + 420)

                if not saw_worker_output and worker_output_marker in normalized:
                    saw_worker_output = True

                if not saw_claude_ui and claude_ui_marker in normalized:
                    saw_claude_ui = True
                    enter_deadline = time.time() + 1

                if saw_claude_ui and not saw_claude_login:
                    for marker, compact_marker in zip(claude_login_markers, compact_markers):
                        if marker in normalized or compact_marker in compact_normalized:
                            saw_claude_login = True
                            first_interrupt_deadline = time.time() + 3
                            break

                if sent_first_interrupt and not saw_exit_confirm and (
                    claude_exit_confirm_marker in normalized
                    or claude_exit_confirm_compact in compact_normalized
                ):
                    saw_exit_confirm = True
                    shell_return_baseline = len(normalized)
                    second_interrupt_deadline = time.time() + 5

                if sent_second_interrupt and shell_prompt_marker in post_exit_normalized:
                    saw_shell_return = True
                    break

            now = time.time()
            if saw_claude_ui and enter_deadline is not None and now >= enter_deadline and not sent_enter:
                os.write(master_fd, b"\r")
                sent_enter = True
                enter_deadline = None
                deadline = max(deadline, now + 60)

            if saw_claude_login and first_interrupt_deadline is not None and now >= first_interrupt_deadline and not sent_first_interrupt:
                os.write(master_fd, b"\x03")
                sent_first_interrupt = True
                first_interrupt_deadline = None
                deadline = max(deadline, now + 45)

            if (saw_exit_confirm or sent_first_interrupt) and second_interrupt_deadline is not None and now >= second_interrupt_deadline and not sent_second_interrupt:
                os.write(master_fd, b"\x03")
                sent_second_interrupt = True
                shell_return_baseline = len(last_normalized)
                second_interrupt_deadline = None
                third_interrupt_deadline = now + 10
                deadline = max(deadline, now + 35)

            if sent_second_interrupt and not saw_shell_return and third_interrupt_deadline is not None and now >= third_interrupt_deadline and not sent_third_interrupt:
                os.write(master_fd, b"\x03")
                sent_third_interrupt = True
                shell_return_baseline = len(last_normalized)
                third_interrupt_deadline = None
                deadline = max(deadline, now + 20)

            if proc.poll() is not None:
                break

        else:
            print("interactive Agent Orchestrator Claude exit smoke timed out", file=sys.stderr)
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            raise SystemExit(1)
    finally:
        try:
            os.close(master_fd)
        except OSError:
            pass

    status = proc.wait()
    sys.stdout.buffer.write(transcript)
    sys.stdout.write(f"\n__STATUS__:{status}\n")

    if not sent_claude:
        print("interactive Agent Orchestrator Claude exit smoke never reached the AO shell banner", file=sys.stderr)
        raise SystemExit(1)

    if not saw_worker_output:
        print("interactive Agent Orchestrator Claude exit smoke never reached worker output", file=sys.stderr)
        raise SystemExit(1)

    if not saw_claude_ui:
        print("interactive Agent Orchestrator Claude exit smoke never reached the theme screen", file=sys.stderr)
        raise SystemExit(1)

    if not saw_claude_login:
        print("interactive Agent Orchestrator Claude exit smoke never reached the login screen", file=sys.stderr)
        raise SystemExit(1)

    if not sent_second_interrupt:
        print("interactive Agent Orchestrator Claude exit smoke never sent the second Ctrl-C", file=sys.stderr)
        raise SystemExit(1)

    if status != 0:
        print("interactive Agent Orchestrator Claude exit smoke terminated the AO VM instead of returning to the shell", file=sys.stderr)
        raise SystemExit(1)

    if not saw_shell_return:
        print("interactive Agent Orchestrator Claude exit smoke did not return to the AO shell prompt", file=sys.stderr)
        raise SystemExit(1)
PY

printf '%s\n' "Agent Orchestrator interactive Claude exit smoke test passed"
