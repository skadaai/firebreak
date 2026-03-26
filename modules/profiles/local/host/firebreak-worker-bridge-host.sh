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

  [ -f "$request_path" ] || return 0
  [ -f "$exit_code_path" ] && return 0
  mkdir "$request_dir/.lock" 2>/dev/null || return 0

  REQUEST_PATH=$request_path \
  WORKER_SCRIPT=$worker_script \
  STDOUT_PATH=$stdout_path \
  STDERR_PATH=$stderr_path \
  EXIT_CODE_PATH=$exit_code_path \
  python3 - <<'PY'
import json
import os
import pty
import subprocess
import threading

request_path = os.environ["REQUEST_PATH"]
worker_script = os.environ["WORKER_SCRIPT"]
stdout_path = os.environ["STDOUT_PATH"]
stderr_path = os.environ["STDERR_PATH"]
exit_code_path = os.environ["EXIT_CODE_PATH"]

try:
    with open(request_path, "r", encoding="utf-8") as handle:
        request = json.load(handle)
    argv = request.get("argv")
    if not isinstance(argv, list) or not argv:
        raise ValueError("request argv must be a non-empty list")
    argv = [str(item) for item in argv]
    if request.get("attach") is True:
        stdin_fifo = request.get("stdin_fifo")
        stdout_fifo = request.get("stdout_fifo")
        if not isinstance(stdin_fifo, str) or not isinstance(stdout_fifo, str):
            raise ValueError("attach requests must provide stdin_fifo and stdout_fifo")

        master_fd, slave_fd = pty.openpty()
        proc = subprocess.Popen(
            ["bash", worker_script, *argv],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=os.environ.copy(),
            close_fds=True,
        )
        os.close(slave_fd)

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
        exit_code = proc.wait()
        try:
            os.close(master_fd)
        except OSError:
            pass
        stdin_thread.join(timeout=1)
        stdout_thread.join(timeout=1)
        stdout = ""
        stderr = ""
    else:
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
except Exception as error:
    stdout = ""
    stderr = f"firebreak worker bridge request failed: {error}\n"
    exit_code = 1

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
