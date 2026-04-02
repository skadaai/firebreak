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
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-vibe-kanban-worker-interactive-codex.XXXXXX")
status=0

cleanup() {
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    printf '%s\n' "preserved interactive vibe-kanban codex smoke artifacts: $smoke_tmp_dir" >&2
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

VIBE_KANBAN_BIN=@VIBE_KANBAN_BIN@ \
SESSION_LOG="$session_log" \
NORMALIZED_LOG="$normalized_log" \
WORKER_STATE_DIR="$worker_state_dir" \
python3 - <<'PY'
import errno
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

bin_path = os.environ["VIBE_KANBAN_BIN"]
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

    outer_marker = "[ vm: firebreak-vibe-kanban | mode: shell | workspace:"
    worker_output_marker = "firebreak: worker produced terminal output"
    codex_auth_marker = "Sign in with ChatGPT"
    codex_continue_marker = "Press Enter to continue"
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

    transcript = bytearray()
    sent_codex = False
    sent_interrupt = False
    saw_worker_output = False
    saw_codex_auth = False
    interrupt_deadline = None
    terminate_deadline = None
    deadline = time.time() + 420
    last_normalized = ""
    try:
        while time.time() < deadline:
            timeout = 0.5
            if interrupt_deadline is not None:
                timeout = max(0.0, min(timeout, interrupt_deadline - time.time()))
            if terminate_deadline is not None:
                timeout = max(0.0, min(timeout, terminate_deadline - time.time()))

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

                if not sent_codex and outer_marker in normalized:
                    os.write(master_fd, b"codex\r")
                    sent_codex = True
                    deadline = max(deadline, time.time() + 300)

                if not saw_worker_output and worker_output_marker in normalized:
                    saw_worker_output = True

                if (
                    not saw_codex_auth
                    and (
                        (
                            codex_auth_marker in normalized
                            and codex_continue_marker in normalized
                        )
                    )
                ):
                    saw_codex_auth = True
                    interrupt_deadline = time.time() + 2

            now = time.time()
            if saw_codex_auth and interrupt_deadline is not None and now >= interrupt_deadline and not sent_interrupt:
                os.write(master_fd, b"\x03")
                sent_interrupt = True
                interrupt_deadline = None
                terminate_deadline = now + 5

            if sent_interrupt and terminate_deadline is not None and now >= terminate_deadline and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
                terminate_deadline = None

            if proc.poll() is not None:
                break
        else:
            print("interactive vibe-kanban codex smoke timed out waiting for attached codex startup", file=sys.stderr)
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

    if not sent_codex:
        print("interactive vibe-kanban codex smoke never reached the vibe-kanban shell banner", file=sys.stderr)
        raise SystemExit(1)

    if not saw_codex_auth:
        print("interactive vibe-kanban codex smoke did not surface the Codex sign-in screen", file=sys.stderr)
        raise SystemExit(1)
PY

printf '%s\n' "Vibe Kanban interactive codex smoke test passed"
