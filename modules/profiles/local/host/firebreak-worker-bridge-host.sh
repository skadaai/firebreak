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
            try:
                tty_attr = termios.tcgetattr(0)
                tty_attr[6][termios.VMIN] = 1
                tty_attr[6][termios.VTIME] = 0
                tty_attr[3] &= ~(
                    termios.ICANON
                    |
                    termios.ECHO
                    | getattr(termios, "ECHOE", 0)
                    | getattr(termios, "ECHOK", 0)
                    | getattr(termios, "ECHONL", 0)
                    | getattr(termios, "ECHOCTL", 0)
                )
                termios.tcsetattr(0, termios.TCSANOW, tty_attr)
            except OSError:
                pass
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
        terminal_rows = request_lines if request_lines is not None else 24
        terminal_columns = request_columns if request_columns is not None else 80
        terminal_state = {"row": 1, "column": 1}
        terminal_query_buffer = bytearray()
        terminal_queries = [
            (b"\x1b[6n", "cursor"),
            (b"\x1b[?u", "kitty-kbd-query"),
            (b"\x1b[c", "da1"),
            (b"\x1b]10;?\x1b\\", "osc10"),
            (b"\x1b]10;?\x07", "osc10"),
            (b"\x1b]11;?\x1b\\", "osc11"),
            (b"\x1b]11;?\x07", "osc11"),
        ]

        def longest_query_prefix(data):
            longest = 0
            for pattern, _ in terminal_queries:
                max_prefix = min(len(pattern) - 1, len(data))
                while max_prefix > longest:
                    if data.endswith(pattern[:max_prefix]):
                        longest = max_prefix
                        break
                    max_prefix -= 1
            return longest

        def write_terminal_reply(response):
            saved_attr = None
            quiet_attr = None
            try:
                current_attr = termios.tcgetattr(master_fd)
                saved_attr = list(current_attr)
                saved_attr[6] = list(current_attr[6])
                quiet_attr = list(current_attr)
                quiet_attr[6] = list(current_attr[6])
                quiet_attr[3] &= ~(
                    termios.ECHO
                    | getattr(termios, "ECHOE", 0)
                    | getattr(termios, "ECHOK", 0)
                    | getattr(termios, "ECHONL", 0)
                    | getattr(termios, "ECHOCTL", 0)
                )
                termios.tcsetattr(master_fd, termios.TCSANOW, quiet_attr)
            except OSError:
                saved_attr = None
            try:
                os.write(master_fd, response)
            finally:
                if saved_attr is not None:
                    try:
                        termios.tcsetattr(master_fd, termios.TCSANOW, saved_attr)
                    except OSError:
                        pass

        def clamp_cursor():
            terminal_state["row"] = max(1, min(terminal_state["row"], terminal_rows))
            terminal_state["column"] = max(1, min(terminal_state["column"], terminal_columns))

        def parse_cursor_params(raw_params):
            params = []
            for item in raw_params.split(";"):
                if item == "":
                    params.append(None)
                    continue
                digits = "".join(ch for ch in item if ch.isdigit())
                params.append(int(digits) if digits else None)
            return params

        def update_terminal_cursor(data):
            index = 0
            data_length = len(data)
            while index < data_length:
                byte = data[index]
                if byte == 0x0D:
                    terminal_state["column"] = 1
                    index += 1
                    continue
                if byte == 0x0A:
                    terminal_state["row"] += 1
                    clamp_cursor()
                    index += 1
                    continue
                if byte == 0x08:
                    terminal_state["column"] = max(1, terminal_state["column"] - 1)
                    index += 1
                    continue
                if byte == 0x1B and index + 1 < data_length:
                    next_byte = data[index + 1]
                    if next_byte == 0x63:
                        terminal_state["row"] = 1
                        terminal_state["column"] = 1
                        index += 2
                        continue
                    if next_byte == 0x5B:
                        seq_end = index + 2
                        while seq_end < data_length and not (0x40 <= data[seq_end] <= 0x7E):
                            seq_end += 1
                        if seq_end >= data_length:
                            break
                        final = chr(data[seq_end])
                        raw_params = data[index + 2:seq_end].decode("ascii", "ignore")
                        params = parse_cursor_params(raw_params)
                        first = params[0] if params else None
                        second = params[1] if len(params) > 1 else None
                        amount = first if first is not None else 1
                        if final in ("H", "f"):
                            terminal_state["row"] = first if first is not None else 1
                            terminal_state["column"] = second if second is not None else 1
                            clamp_cursor()
                        elif final == "A":
                            terminal_state["row"] -= amount
                            clamp_cursor()
                        elif final == "B":
                            terminal_state["row"] += amount
                            clamp_cursor()
                        elif final == "C":
                            terminal_state["column"] += amount
                            clamp_cursor()
                        elif final == "D":
                            terminal_state["column"] -= amount
                            clamp_cursor()
                        elif final == "E":
                            terminal_state["row"] += amount
                            terminal_state["column"] = 1
                            clamp_cursor()
                        elif final == "F":
                            terminal_state["row"] -= amount
                            terminal_state["column"] = 1
                            clamp_cursor()
                        elif final == "G":
                            terminal_state["column"] = first if first is not None else 1
                            clamp_cursor()
                        elif final == "d":
                            terminal_state["row"] = first if first is not None else 1
                            clamp_cursor()
                        index = seq_end + 1
                        continue
                    if next_byte == 0x5D:
                        osc_end = data.find(b"\x07", index + 2)
                        st_end = data.find(b"\x1b\\", index + 2)
                        candidates = [end for end in (osc_end, st_end) if end >= 0]
                        if not candidates:
                            break
                        end_index = min(candidates)
                        index = end_index + (1 if end_index == osc_end else 2)
                        continue
                    if next_byte == 0x50:
                        dcs_end = data.find(b"\x1b\\", index + 2)
                        if dcs_end < 0:
                            break
                        index = dcs_end + 2
                        continue
                if 0x20 <= byte <= 0x7E:
                    if terminal_state["column"] < terminal_columns:
                        terminal_state["column"] += 1
                    else:
                        terminal_state["column"] = terminal_columns
                index += 1

        def build_terminal_reply(query_name):
            if query_name == "cursor":
                clamp_cursor()
                return f"\x1b[{terminal_state['row']};{terminal_state['column']}R".encode("ascii")
            if query_name == "kitty-kbd-query":
                return b"\x1b[?0u"
            if query_name == "da1":
                return b"\x1b[?62;1;2;6;22c"
            if query_name == "osc10":
                return b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"
            if query_name == "osc11":
                return b"\x1b]11;rgb:0000/0000/0000\x1b\\"
            return b""

        def handle_terminal_queries(chunk):
            terminal_query_buffer.extend(chunk)
            data = bytes(terminal_query_buffer)
            forwarded = bytearray()
            index = 0

            while True:
                next_match = None
                for pattern, query_name in terminal_queries:
                    match_index = data.find(pattern, index)
                    if match_index < 0:
                        continue
                    if next_match is None or match_index < next_match[0]:
                        next_match = (match_index, pattern, query_name)
                if next_match is None:
                    break
                match_index, pattern, query_name = next_match
                segment = data[index:match_index]
                forwarded.extend(segment)
                update_terminal_cursor(segment)
                trace(f"attach-term-query:{query_name}")
                response = build_terminal_reply(query_name)
                try:
                    write_terminal_reply(response)
                    trace(f"attach-term-reply:{query_name}:{response.hex()}")
                except OSError:
                    pass
                index = match_index + len(pattern)

            remainder = data[index:]
            keep = longest_query_prefix(remainder)
            if keep > 0:
                visible = remainder[:-keep]
                forwarded.extend(visible)
                update_terminal_cursor(visible)
                terminal_query_buffer[:] = remainder[-keep:]
            else:
                forwarded.extend(remainder)
                update_terminal_cursor(remainder)
                terminal_query_buffer.clear()

            return bytes(forwarded)

        def pump_stdin():
            offset = 0
            saw_input = False
            total_input_bytes = 0
            sample_budget = 64
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
                            trace(f"attach-stdin-first-chunk-hex:{chunk[:32].hex()}")
                            saw_input = True
                        if sample_budget > 0:
                            sample = chunk[:sample_budget]
                            trace(f"attach-stdin-sample-hex:{sample.hex()}")
                            sample_budget -= len(sample)
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
                        forwarded = handle_terminal_queries(chunk)
                        if forwarded:
                            sink.write(forwarded)
                            sink.flush()
                if terminal_query_buffer:
                    sink.write(bytes(terminal_query_buffer))
                    sink.flush()
                    terminal_query_buffer.clear()
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
