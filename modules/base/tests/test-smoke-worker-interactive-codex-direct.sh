#!/usr/bin/env bash
set -eu

default_firebreak_tmpdir=${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}
if [ -d /cache ] && [ -w /cache ]; then
  default_firebreak_tmpdir=/cache/firebreak
fi

choose_tmp_root() {
  if [ -n "${FIREBREAK_TEST_TMPDIR:-}" ]; then
    printf '%s\n' "$FIREBREAK_TEST_TMPDIR"
    return
  fi

  for candidate in \
    "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/firebreak-test/tmp" \
    "${FIREBREAK_TMPDIR:-$default_firebreak_tmpdir}/firebreak/tmp" \
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
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-interactive-codex-direct.XXXXXX")

cleanup() {
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    printf '%s\n' "preserved direct interactive Codex smoke artifacts: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}

status=0
session_log=$smoke_tmp_dir/session.log
normalized_log=$smoke_tmp_dir/session.normalized.log
worker_state_dir=$smoke_tmp_dir/worker-state
firebreak_state_dir=$smoke_tmp_dir/firebreak-state
workspace_dir=$smoke_tmp_dir/workspace
mkdir -p "$worker_state_dir" "$firebreak_state_dir" "$workspace_dir"

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

SESSION_LOG="$session_log" \
NORMALIZED_LOG="$normalized_log" \
WORKER_STATE_DIR="$worker_state_dir" \
FIREBREAK_STATE_DIR="$firebreak_state_dir" \
WORKSPACE_DIR="$workspace_dir" \
FIREBREAK_BIN=@FIREBREAK_BIN@ \
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

firebreak_bin = os.environ["FIREBREAK_BIN"]
log_path = os.environ["SESSION_LOG"]
normalized_log_path = os.environ["NORMALIZED_LOG"]
workspace_dir = os.environ["WORKSPACE_DIR"]

env = os.environ.copy()
env["FIREBREAK_INSTANCE_EPHEMERAL"] = "1"
env["FIREBREAK_WORKER_STATE_DIR"] = os.environ["WORKER_STATE_DIR"]
env["FIREBREAK_STATE_DIR"] = os.environ["FIREBREAK_STATE_DIR"]
env["FIREBREAK_DEBUG_KEEP_RUNTIME"] = "1"
env["FIREBREAK_FLAKE_REF"] = "path:@REPO_ROOT@"
env["FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG"] = "1"
env["FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES"] = "nix-command flakes"

master_fd, slave_fd = pty.openpty()
rows = 51
cols = 114
winsize = struct.pack("HHHH", rows, cols, 0, 0)
fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

command = [
    firebreak_bin,
    "worker",
    "run",
    "--attach",
    "--backend",
    "firebreak",
    "--kind",
    "codex",
    "--workspace",
    workspace_dir,
    "--package",
    "firebreak-codex",
    "--launch-mode",
    "run",
    "--",
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

with open(log_path, "wb") as log_file, open(normalized_log_path, "w", encoding="utf-8") as normalized_log_file:
    proc = subprocess.Popen(
        command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        env=env,
        close_fds=True,
    )
    os.close(slave_fd)

    transcript = bytearray()
    saw_auth = False
    deadline = time.time() + 420
    last_normalized = ""
    try:
        while time.time() < deadline:
            readable, _, _ = select.select([master_fd], [], [], 0.5)
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
                if (
                    "welcometocodex" in compact_normalized
                    and "signinwithchatgpt" in compact_normalized
                    and "pressentertocontinue" in compact_normalized
                ):
                    saw_auth = True
                    break
            if proc.poll() is not None:
                break
        else:
            print("direct interactive Codex smoke timed out waiting for attach completion", file=sys.stderr)
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

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    status = proc.returncode
    sys.stdout.buffer.write(transcript)
    sys.stdout.write(f"\n__STATUS__:{status}\n")

    if not saw_auth:
        print("direct interactive Codex smoke did not surface the Codex sign-in screen", file=sys.stderr)
        raise SystemExit(1)
PY

printf '%s\n' "Direct interactive Codex smoke test passed"
