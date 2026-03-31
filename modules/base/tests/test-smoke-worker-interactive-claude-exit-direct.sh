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
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-interactive-claude-exit-direct.XXXXXX")

cleanup() {
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    printf '%s\n' "preserved direct interactive Claude exit smoke artifacts: $smoke_tmp_dir" >&2
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
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

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
    "claude-code",
    "--workspace",
    workspace_dir,
    "--package",
    "firebreak-claude-code",
    "--vm-mode",
    "run",
    "--",
]

with open(log_path, "wb") as log_file:
    normalized_log_file = open(normalized_log_path, "w", encoding="utf-8")
    proc = subprocess.Popen(
        command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        env=env,
        close_fds=True,
    )
    os.close(slave_fd)

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

    claude_ui_marker = "MonokaiExtended"
    claude_login_markers = [
        "/login",
        "Claude Pro",
        "Anthropic Console",
        "Amazon Bedrock",
        "Google Vertex AI",
        "Microsoft Foundry",
    ]
    exit_confirm_marker = "Press Ctrl-C again to exit"
    exit_confirm_compact = compact(exit_confirm_marker)
    login_compact_markers = [compact(marker) for marker in claude_login_markers]

    transcript = bytearray()
    saw_claude_ui = False
    saw_claude_login = False
    saw_exit_confirm = False
    sent_down = False
    sent_enter = False
    sent_first_interrupt = False
    sent_second_interrupt = False
    ui_seen_at = None
    login_seen_at = None
    exit_confirm_seen_at = None
    proc_exited_after_first_interrupt = False
    last_normalized = ""
    deadline = time.time() + 480

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

                if not saw_claude_ui and claude_ui_marker in normalized:
                    saw_claude_ui = True
                    ui_seen_at = time.time()

                if saw_claude_ui and not saw_claude_login:
                    for marker, compact_marker in zip(claude_login_markers, login_compact_markers):
                        if marker in normalized or compact_marker in compact_normalized:
                            saw_claude_login = True
                            login_seen_at = time.time()
                            break

                if sent_first_interrupt and not saw_exit_confirm and (
                    exit_confirm_marker in normalized
                    or exit_confirm_compact in compact_normalized
                ):
                    saw_exit_confirm = True
                    exit_confirm_seen_at = time.time()

            now = time.time()
            if ui_seen_at is not None and not sent_down and now - ui_seen_at >= 1:
                os.write(master_fd, b"\x1b[B")
                sent_down = True

            if ui_seen_at is not None and not sent_enter and now - ui_seen_at >= 3:
                os.write(master_fd, b"\r")
                sent_enter = True

            if login_seen_at is not None and not sent_first_interrupt and now - login_seen_at >= 3:
                os.write(master_fd, b"\x03")
                sent_first_interrupt = True

            if sent_first_interrupt and proc.poll() is not None and not saw_exit_confirm:
                proc_exited_after_first_interrupt = True
                break

            if exit_confirm_seen_at is not None and not sent_second_interrupt and now - exit_confirm_seen_at >= 3:
                os.write(master_fd, b"\x03")
                sent_second_interrupt = True

            if sent_second_interrupt and proc.poll() is not None:
                break

            if proc.poll() is not None:
                break
        else:
            print("direct interactive Claude exit smoke timed out", file=sys.stderr)
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            raise SystemExit(1)
    finally:
        normalized_log_file.close()
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

    normalized = normalize(transcript)
    if not saw_claude_ui:
        print("direct interactive Claude exit smoke did not surface the Claude theme selection UI", file=sys.stderr)
        raise SystemExit(1)

    if not saw_claude_login:
        print("direct interactive Claude exit smoke did not advance to the login selection screen", file=sys.stderr)
        raise SystemExit(1)

    if proc_exited_after_first_interrupt:
        print("direct interactive Claude exit smoke exited immediately after the first Ctrl-C", file=sys.stderr)
        raise SystemExit(1)

    if not saw_exit_confirm:
        print("direct interactive Claude exit smoke never surfaced the exit confirmation prompt", file=sys.stderr)
        raise SystemExit(1)

    if not sent_second_interrupt:
        print("direct interactive Claude exit smoke never sent the second Ctrl-C", file=sys.stderr)
        raise SystemExit(1)

    if status != 0:
        print("direct interactive Claude exit smoke did not end cleanly after the second Ctrl-C", file=sys.stderr)
        raise SystemExit(1)
PY

printf '%s\n' "Direct interactive Claude exit smoke test passed"
