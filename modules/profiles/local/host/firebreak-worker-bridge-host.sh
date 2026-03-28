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
import shutil
import subprocess
import threading
import time
import fcntl
import struct
import termios

request_path = os.environ["REQUEST_PATH"]
worker_script = os.environ["WORKER_SCRIPT"]
stdout_path = os.environ["STDOUT_PATH"]
stderr_path = os.environ["STDERR_PATH"]
exit_code_path = os.environ["EXIT_CODE_PATH"]
trace_path = os.environ["TRACE_PATH"]
request_dir = os.path.dirname(request_path)
worker_root_path = os.path.join(request_dir, "worker-root")
worker_root_cache = None
trace_mirrored = False


def resolve_worker_root():
    global worker_root_cache, trace_mirrored
    if worker_root_cache and os.path.isdir(worker_root_cache):
        return worker_root_cache
    try:
        candidate = open(worker_root_path, "r", encoding="utf-8").read().strip()
    except OSError:
        return None
    if not candidate or not os.path.isdir(candidate):
        return None
    worker_root_cache = candidate
    if not trace_mirrored and os.path.exists(trace_path):
        try:
            shutil.copyfile(trace_path, os.path.join(candidate, "bridge-request-trace.log"))
            trace_mirrored = True
        except OSError:
            pass
    return worker_root_cache


def persist_response_exit_code(code: int) -> None:
    worker_root = resolve_worker_root()
    if not worker_root:
        return
    try:
        with open(os.path.join(worker_root, "bridge-request-response-exit-code"), "w", encoding="utf-8") as handle:
            handle.write(f"{code}\n")
    except OSError:
        pass

def trace(message: str) -> None:
    with open(trace_path, "a", encoding="utf-8") as handle:
        handle.write(message + "\n")
    worker_root = resolve_worker_root()
    if not worker_root:
        return
    try:
        with open(os.path.join(worker_root, "bridge-request-trace.log"), "a", encoding="utf-8") as handle:
            handle.write(message + "\n")
    except OSError:
        pass


def parse_positive_dimension(value):
    text = str(value or "").strip()
    if not text.isdigit():
        return None
    parsed = int(text)
    return parsed if parsed > 0 else None


def normalize_term(value):
    term = str(value or "").strip()
    if not term:
        return ""
    legacy_terms = {
        "ansi",
        "dumb",
        "vt100",
        "vt102",
        "vt220",
    }
    if term.lower() in legacy_terms:
        return "xterm-256color"
    return term

try:
    trace("request-loaded")
    with open(request_path, "r", encoding="utf-8") as handle:
        request = json.load(handle)
    argv = request.get("argv")
    if not isinstance(argv, list) or not argv:
        raise ValueError("request argv must be a non-empty list")
    argv = [str(item) for item in argv]
    request_term = str(request.get("term") or "")
    effective_term = normalize_term(request_term)
    request_columns = parse_positive_dimension(request.get("columns"))
    request_lines = parse_positive_dimension(request.get("lines"))
    if request.get("attach") is True and request.get("interactive") is True:
        stdin_stream = os.path.join(request_dir, "stdin.stream")
        stdout_stream = os.path.join(request_dir, "stdout.stream")
        stdin_eof_path = os.path.join(request_dir, "stdin.eof")
        if not os.path.exists(stdin_stream) or not os.path.exists(stdout_stream):
            raise ValueError("attach requests must create stdin.stream and stdout.stream in the request directory")

        trace(f"attach-term-requested:{request_term or 'unset'}")
        trace(f"attach-term-effective:{effective_term or 'unset'}")
        if request_lines is not None and request_columns is not None:
            trace(f"attach-size:{request_lines}x{request_columns}")
        else:
            trace("attach-size:unset")
        trace("attach-pty-open")
        child_pid, master_fd = pty.fork()
        if child_pid == 0:
            child_env = os.environ.copy()
            child_env["FIREBREAK_WORKER_BRIDGE_REQUEST_DIR"] = request_dir
            child_env["FIREBREAK_WORKER_BRIDGE_TRACE_PATH"] = trace_path
            if effective_term:
                child_env["TERM"] = effective_term
            if request_columns is not None:
                child_env["COLUMNS"] = str(request_columns)
            if request_lines is not None:
                child_env["LINES"] = str(request_lines)
            os.execvpe("bash", ["bash", worker_script, *argv], child_env)
        if request_columns is not None and request_lines is not None:
            winsize = struct.pack("HHHH", request_lines, request_columns, 0, 0)
            try:
                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
            except OSError:
                pass
        trace("attach-worker-started")

        def pump_stdin():
            offset = 0
            saw_input = False
            total_input_bytes = 0
            try:
                trace("attach-stdin-stream-opened")
                while True:
                    with open(stdin_stream, "rb") as source:
                        source.seek(offset)
                        chunk = source.read(4096)
                    if chunk:
                        offset += len(chunk)
                        total_input_bytes += len(chunk)
                        if not saw_input:
                            trace("attach-stdin-first-byte")
                            saw_input = True
                        os.write(master_fd, chunk)
                        continue
                    if os.path.exists(stdin_eof_path):
                        trace("attach-stdin-eof")
                        break
                    time.sleep(0.1)
            except OSError:
                pass
            finally:
                if saw_input:
                    trace(f"attach-stdin-total-bytes:{total_input_bytes}")

        def pump_stdout():
            saw_output = False
            try:
                trace("attach-stdout-stream-opened")
                with open(stdout_stream, "ab", buffering=0) as sink:
                    while True:
                        try:
                            chunk = os.read(master_fd, 4096)
                        except OSError:
                            break
                        if not chunk:
                            trace("attach-stdout-eof")
                            break
                        if not saw_output:
                            trace("attach-stdout-first-byte")
                            saw_output = True
                        sink.write(chunk)
                        sink.flush()
            except OSError:
                pass

        stdin_thread = threading.Thread(target=pump_stdin, daemon=True)
        stdout_thread = threading.Thread(target=pump_stdout, daemon=True)
        stdin_thread.start()
        stdout_thread.start()
        _, wait_status = os.waitpid(child_pid, 0)
        trace("attach-waitpid-returned")
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
            env={
                **os.environ.copy(),
                "FIREBREAK_WORKER_BRIDGE_REQUEST_DIR": os.path.dirname(request_path),
                "FIREBREAK_WORKER_BRIDGE_TRACE_PATH": trace_path,
            },
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
            env={
                **os.environ.copy(),
                "FIREBREAK_WORKER_BRIDGE_REQUEST_DIR": os.path.dirname(request_path),
                "FIREBREAK_WORKER_BRIDGE_TRACE_PATH": trace_path,
            },
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
persist_response_exit_code(exit_code)
trace("response-written")
PY
}

while :; do
  for request_dir in "$bridge_dir"/requests/*; do
    [ -d "$request_dir" ] || continue
    process_request "$request_dir"
  done
  sleep 0.1
done
