set -eu

default_firebreak_tmpdir=${TMPDIR:-/tmp}
if [ -d /cache ] && [ -w /cache ]; then
  default_firebreak_tmpdir=/cache/firebreak
fi

firebreak_tmp_root=${FIREBREAK_TMPDIR:-$default_firebreak_tmpdir}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-worker-guest-bridge-interactive.XXXXXX")
keep_smoke_tmp_dir=0
cleanup() {
  if [ "$keep_smoke_tmp_dir" = "1" ]; then
    printf '%s\n' "preserved interactive smoke artifacts: $smoke_tmp_dir" >&2
    return
  fi
  rm -rf "$smoke_tmp_dir"
}
trap cleanup EXIT INT TERM

workspace_dir=$smoke_tmp_dir/workspace
state_dir=$smoke_tmp_dir/state
firebreak_state_dir=$smoke_tmp_dir/firebreak-state
mkdir -p "$workspace_dir" "$state_dir" "$firebreak_state_dir"

guest_script=$workspace_dir/guest-bridge-interactive-check.sh
cat >"$guest_script" <<'EOF'
set -eu

python3 - <<'PY'
import os
import pty
import select
import sys
import time

command = [
    "firebreak",
    "worker",
    "run",
    "--kind",
    "bridge-interactive-firebreak",
    "--workspace",
    os.getcwd(),
    "--attach",
    "--",
]

master_fd, slave_fd = pty.openpty()
child_pid = os.fork()
if child_pid == 0:
    os.setsid()
    os.login_tty(slave_fd)
    os.execvp(command[0], command)
os.close(slave_fd)

output = bytearray()
ready_seen = False
input_attempts = 0
last_input_sent_at = 0.0
child_wait_status = None
deadline = time.monotonic() + 300

try:
    while True:
        if time.monotonic() >= deadline:
            timed_out_output = output.decode("utf-8", errors="replace")
            sys.stderr.write(timed_out_output)
            if timed_out_output and not timed_out_output.endswith("\n"):
                sys.stderr.write("\n")
            os.kill(child_pid, 9)
            raise SystemExit("interactive guest bridge smoke timed out waiting for attach completion")

        readable, _, _ = select.select([master_fd], [], [], 0.2)
        if master_fd in readable:
            try:
                chunk = os.read(master_fd, 4096)
            except OSError:
                chunk = b""
            if not chunk:
                break
            output.extend(chunk)
            if b"READY" in output:
                ready_seen = True
            if ready_seen and b"ECHO:ping" not in output:
                now = time.monotonic()
                if input_attempts == 0 or now - last_input_sent_at >= 5.0:
                    os.write(master_fd, b"ping\n")
                    input_attempts += 1
                    last_input_sent_at = now
            continue

        waited_pid, wait_status = os.waitpid(child_pid, os.WNOHANG)
        if waited_pid == child_pid:
            child_wait_status = wait_status
            try:
                chunk = os.read(master_fd, 4096)
            except OSError:
                chunk = b""
            if chunk:
                output.extend(chunk)
                if b"READY" in output:
                    ready_seen = True
                if ready_seen and b"ECHO:ping" not in output:
                    now = time.monotonic()
                    if input_attempts == 0 or now - last_input_sent_at >= 5.0:
                        os.write(master_fd, b"ping\n")
                        input_attempts += 1
                        last_input_sent_at = now
                continue
            break
finally:
    os.close(master_fd)

if child_wait_status is None:
    _, child_wait_status = os.waitpid(child_pid, 0)
wait_status = child_wait_status
if os.WIFEXITED(wait_status):
    exit_code = os.WEXITSTATUS(wait_status)
elif os.WIFSIGNALED(wait_status):
    exit_code = 128 + os.WTERMSIG(wait_status)
else:
    exit_code = 1
attach_output = output.decode("utf-8", errors="replace")

sys.stdout.write("__BRIDGE_INTERACTIVE_ATTACH__\n")
sys.stdout.write(attach_output)
if not attach_output.endswith("\n"):
    sys.stdout.write("\n")

if "READY" not in attach_output:
    sys.stderr.write(attach_output)
    sys.stderr.write("\ninteractive guest bridge smoke did not receive the ready marker\n")
    raise SystemExit(1)

if "ECHO:ping" not in attach_output:
    sys.stderr.write(attach_output)
    sys.stderr.write(f"\ninteractive guest bridge smoke sent ping {input_attempts} time(s)\n")
    sys.stderr.write("\ninteractive guest bridge smoke did not receive the echoed input\n")
    raise SystemExit(1)

if exit_code != 0:
    sys.stderr.write(attach_output)
    sys.stderr.write(f"\ninteractive guest bridge smoke expected exit code 0, got {exit_code}\n")
    raise SystemExit(1)

print("__BRIDGE_INTERACTIVE_OK__")
PY
EOF

if ! output=$(
  cd "$workspace_dir"
  env -u AGENT_CONFIG -u AGENT_CONFIG_HOST_PATH -u CODEX_CONFIG -u CODEX_CONFIG_HOST_PATH -u CLAUDE_CONFIG -u CLAUDE_CONFIG_HOST_PATH \
    FIREBREAK_WORKER_STATE_DIR="$state_dir" \
    FIREBREAK_STATE_DIR="$firebreak_state_dir" \
    FIREBREAK_DEBUG_KEEP_RUNTIME=1 \
    FIREBREAK_INSTANCE_EPHEMERAL=1 @BRIDGE_VM_BIN@ "$guest_script" 2>&1
); then
  keep_smoke_tmp_dir=1
  printf '%s\n' "$output" >&2
  printf '%s\n' '--- host worker debug --json ---' >&2
  FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ worker debug --json >&2 || true
  echo "worker guest bridge interactive smoke failed before completion" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q '__BRIDGE_INTERACTIVE_OK__'; then
  keep_smoke_tmp_dir=1
  printf '%s\n' "$output" >&2
  printf '%s\n' '--- host worker debug --json ---' >&2
  FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ worker debug --json >&2 || true
  echo "worker guest bridge interactive smoke did not complete successfully" >&2
  exit 1
fi

debug_json=$(FIREBREAK_WORKER_STATE_DIR="$state_dir" @AGENT_BIN@ worker debug --json)
if ! printf '%s\n' "$debug_json" | grep -F -q 'cursor-reply-hex:'; then
  keep_smoke_tmp_dir=1
  printf '%s\n' "$output" >&2
  printf '%s\n' '--- host worker debug --json ---' >&2
  printf '%s\n' "$debug_json" >&2
  echo "worker guest bridge interactive smoke did not observe any cursor-position reply" >&2
  exit 1
fi

if printf '%s\n' "$debug_json" | grep -F -q 'cursor-reply-hex:missing'; then
  keep_smoke_tmp_dir=1
  printf '%s\n' "$output" >&2
  printf '%s\n' '--- host worker debug --json ---' >&2
  printf '%s\n' "$debug_json" >&2
  echo "worker guest bridge interactive smoke observed a missing cursor-position reply" >&2
  exit 1
fi

printf '%s\n' "Firebreak worker guest bridge interactive smoke test passed"
