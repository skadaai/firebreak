set -eu

bridge_dir=$1
worker_script=$2

mkdir -p "$bridge_dir/requests"

process_request() {
  request_dir=$1
  request_path=$request_dir/request.json
  stdout_path=$request_dir/response.stdout
  stderr_path=$request_dir/response.stderr
  exit_code_path=$request_dir/response.exit-code
  trace_path=$request_dir/trace.log

  [ -f "$request_path" ] || return 0
  [ -f "$exit_code_path" ] && return 0
  mkdir "$request_dir/.lock" 2>/dev/null || return 0

  REQUEST_PATH=$request_path \
  WORKER_SCRIPT=$worker_script \
  STDOUT_PATH=$stdout_path \
  STDERR_PATH=$stderr_path \
  EXIT_CODE_PATH=$exit_code_path \
  TRACE_PATH=$trace_path \
  python3 - <<'PY'
import json
import os
import pty
import subprocess
import threading
import fcntl
import struct
import termios

request_path = os.environ["REQUEST_PATH"]
worker_script = os.environ["WORKER_SCRIPT"]
stdout_path = os.environ["STDOUT_PATH"]
stderr_path = os.environ["STDERR_PATH"]
exit_code_path = os.environ["EXIT_CODE_PATH"]
trace_path = os.environ["TRACE_PATH"]

def trace(message: str) -> None:
    with open(trace_path, "a", encoding="utf-8") as handle:
        handle.write(message + "\n")

try:
    trace("request-loaded")
    with open(request_path, "r", encoding="utf-8") as handle:
        request = json.load(handle)
    argv = request.get("argv")
    if not isinstance(argv, list) or not argv:
        raise ValueError("request argv must be a non-empty list")
    argv = [str(item) for item in argv]
    request_term = str(request.get("term") or "")
    request_columns = str(request.get("columns") or "")
    request_lines = str(request.get("lines") or "")
    if request.get("attach") is True and request.get("interactive") is True:
        request_dir = os.path.dirname(request_path)
        stdin_fifo = os.path.join(request_dir, "stdin.pipe")
        stdout_fifo = os.path.join(request_dir, "stdout.pipe")
        if not os.path.exists(stdin_fifo) or not os.path.exists(stdout_fifo):
            raise ValueError("attach requests must create stdin.pipe and stdout.pipe in the request directory")

        trace("attach-pty-open")
        child_pid, master_fd = pty.fork()
        if child_pid == 0:
            child_env = os.environ.copy()
            if request_term:
                child_env["TERM"] = request_term
            if request_columns:
                child_env["COLUMNS"] = request_columns
            if request_lines:
                child_env["LINES"] = request_lines
            os.execvpe("bash", ["bash", worker_script, *argv], child_env)
        if request_columns.isdigit() and request_lines.isdigit():
            winsize = struct.pack("HHHH", int(request_lines), int(request_columns), 0, 0)
            try:
                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
            except OSError:
                pass
        trace("attach-worker-started")

        def pump_stdin():
            try:
                with open(stdin_fifo, "rb", buffering=0) as source:
                    while True:
                        chunk = source.read(4096)
                        if not chunk:
                            break
                        os.write(master_fd, chunk)
            except OSError:
                pass

        def pump_stdout():
            try:
                with open(stdout_fifo, "wb", buffering=0) as sink:
                    while True:
                        try:
                            chunk = os.read(master_fd, 4096)
                        except OSError:
                            break
                        if not chunk:
                            break
                        sink.write(chunk)
                        sink.flush()
            except OSError:
                pass

        stdin_thread = threading.Thread(target=pump_stdin, daemon=True)
        stdout_thread = threading.Thread(target=pump_stdout, daemon=True)
        stdin_thread.start()
        stdout_thread.start()
        _, wait_status = os.waitpid(child_pid, 0)
        if os.WIFEXITED(wait_status):
            exit_code = os.WEXITSTATUS(wait_status)
        elif os.WIFSIGNALED(wait_status):
            exit_code = 128 + os.WTERMSIG(wait_status)
        else:
            exit_code = 1
        trace(f"attach-worker-exit:{exit_code}")
        stdin_thread.join(timeout=1)
        stdout_thread.join(timeout=5)
        try:
            os.close(master_fd)
        except OSError:
            pass
        stdout_thread.join(timeout=1)
        stdout = ""
        stderr = ""
    elif request.get("attach") is True:
        trace("attach-noninteractive-start")
        result = subprocess.run(
            ["bash", worker_script, *argv],
            capture_output=True,
            text=True,
            env=os.environ.copy(),
            check=False,
        )
        stdout = result.stdout
        stderr = result.stderr
        exit_code = result.returncode
        trace(f"attach-noninteractive-exit:{exit_code}")
    else:
        trace("detached-worker-start")
        result = subprocess.run(
            ["bash", worker_script, *argv],
            capture_output=True,
            text=True,
            env=os.environ.copy(),
            check=False,
        )
        stdout = result.stdout
        stderr = result.stderr
        exit_code = result.returncode
        trace(f"detached-worker-exit:{exit_code}")
except Exception as error:
    stdout = ""
    stderr = f"firebreak worker bridge request failed: {error}\n"
    exit_code = 1
    trace(f"bridge-error:{error}")

with open(stdout_path, "w", encoding="utf-8") as handle:
    handle.write(stdout)
with open(stderr_path, "w", encoding="utf-8") as handle:
    handle.write(stderr)
with open(exit_code_path, "w", encoding="utf-8") as handle:
    handle.write(f"{exit_code}\n")
PY
}

while :; do
  for request_dir in "$bridge_dir"/requests/*; do
    [ -d "$request_dir" ] || continue
    process_request "$request_dir"
  done
  sleep 0.1
done
