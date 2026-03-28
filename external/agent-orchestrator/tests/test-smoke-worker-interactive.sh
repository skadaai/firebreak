set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-agent-orchestrator-worker-interactive.XXXXXX")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    printf '%s\n' "preserved interactive AO smoke artifacts: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

session_log=$smoke_tmp_dir/session.log

AGENT_ORCHESTRATOR_BIN=@AGENT_ORCHESTRATOR_BIN@ \
SESSION_LOG="$session_log" \
python3 - <<'PY'
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

bin_path = os.environ["AGENT_ORCHESTRATOR_BIN"]
log_path = os.environ["SESSION_LOG"]

env = os.environ.copy()
env["FIREBREAK_INSTANCE_EPHEMERAL"] = "1"
env["FIREBREAK_VM_MODE"] = "shell"

master_fd, slave_fd = pty.openpty()

with open(log_path, "wb") as log_file:
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
    inner_welcome = "Welcome to Skada Firebreak - reliable isolation for high-trust automation"
    inner_marker = "[ vm: firebreak-codex | mode: agent-attach-exec | workspace:"
    inner_boot_marker = "hostname=firebreak-codex"
    worker_output_marker = "firebreak: worker produced terminal output"
    ansi_pattern = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

    transcript = bytearray()
    sent_codex = False
    sent_interrupt = False
    saw_worker_output = False
    saw_inner = False
    saw_inner_banner = False
    interrupt_deadline = None
    terminate_deadline = None
    deadline = time.time() + 240

    try:
        while time.time() < deadline:
            timeout = 0.5
            if interrupt_deadline is not None:
                timeout = max(0.0, min(timeout, interrupt_deadline - time.time()))
            if terminate_deadline is not None:
                timeout = max(0.0, min(timeout, terminate_deadline - time.time()))

            readable, _, _ = select.select([master_fd], [], [], timeout)
            if readable:
                chunk = os.read(master_fd, 65536)
                if not chunk:
                    break
                transcript.extend(chunk)
                log_file.write(chunk)
                log_file.flush()
                normalized = ansi_pattern.sub("", transcript.decode("utf-8", "ignore")).replace("\r", "\n")

                if not sent_codex and outer_marker in normalized:
                    os.write(master_fd, b"codex\r")
                    sent_codex = True

                if not saw_worker_output and worker_output_marker in normalized:
                    saw_worker_output = True

                if not saw_inner_banner and inner_welcome in normalized and inner_marker in normalized:
                    saw_inner = True
                    saw_inner_banner = True
                    interrupt_deadline = time.time() + 5
                elif not saw_inner and saw_worker_output and inner_boot_marker in normalized:
                    saw_inner = True
                    interrupt_deadline = time.time() + 5

            now = time.time()
            if saw_inner and interrupt_deadline is not None and now >= interrupt_deadline and not sent_interrupt:
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
            print("interactive Agent Orchestrator smoke timed out waiting for attached codex startup", file=sys.stderr)
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
        print("interactive Agent Orchestrator smoke never reached the AO shell banner", file=sys.stderr)
        raise SystemExit(1)

    if not saw_inner:
        print("interactive Agent Orchestrator smoke did not surface nested firebreak-codex terminal output", file=sys.stderr)
        raise SystemExit(1)

    if not saw_worker_output:
        print("interactive Agent Orchestrator smoke did not report attached worker output", file=sys.stderr)
        raise SystemExit(1)
PY

printf '%s\n' "Agent Orchestrator interactive codex smoke test passed"
