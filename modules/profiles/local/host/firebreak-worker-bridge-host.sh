#!/usr/bin/env bash
set -eu

bridge_dir=$1
worker_script=$2
poll_interval=${FIREBREAK_WORKER_BRIDGE_POLL_INTERVAL:-0.25}

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
  lock_dir=$request_dir/.lock
  if ! mkdir "$lock_dir" 2>/dev/null; then
    if [ -r "$lock_dir/pid" ]; then
      lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
      case "$lock_pid" in
        ""|*[!0-9]*) ;;
        *)
          if ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -rf "$lock_dir"
          fi
          ;;
      esac
    fi
    mkdir "$lock_dir" 2>/dev/null || return 0
  fi
  printf '%s\n' "${BASHPID:-$$}" >"$lock_dir/pid"

  REQUEST_DIR=$request_dir \
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
request_dir = os.environ["REQUEST_DIR"]
worker_id_path = os.path.join(request_dir, "worker-id")
worker_root_cache = None
xdg_state_home = os.environ.get("XDG_STATE_HOME")
home_dir = os.environ.get("HOME") or "/tmp"
default_state_home = xdg_state_home or os.path.join(home_dir, ".local", "state")
worker_state_dir = os.environ.get("FIREBREAK_WORKER_STATE_DIR") or os.path.join(default_state_home, "firebreak", "worker-broker")
workers_root = os.path.realpath(os.path.join(worker_state_dir, "workers"))
runtime_metadata_cache = None
attach_stage_path_cache = None
command_signal_stream_path_cache = None
trace_mirrored = False
poll_interval = 0.005
bridge_host_workspace = os.environ.get("FIREBREAK_WORKER_BRIDGE_HOST_WORKSPACE", "")
bridge_guest_workspace = os.environ.get("FIREBREAK_WORKER_BRIDGE_GUEST_WORKSPACE", "")


def valid_worker_id(worker_id: str) -> bool:
    return bool(worker_id) and all(ch.isalnum() or ch in "-._" for ch in worker_id)


def resolve_worker_root():
    global worker_root_cache, trace_mirrored
    if worker_root_cache and os.path.isdir(worker_root_cache):
        return worker_root_cache
    try:
        worker_id = open(worker_id_path, "r", encoding="utf-8").read().strip()
    except OSError:
        return None
    if not valid_worker_id(worker_id):
        return None
    candidate = os.path.realpath(os.path.join(workers_root, worker_id))
    try:
        if os.path.commonpath([workers_root, candidate]) != workers_root:
            return None
    except ValueError:
        return None
    if not os.path.isdir(candidate):
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


def resolve_runtime_metadata():
    global runtime_metadata_cache, attach_stage_path_cache, command_signal_stream_path_cache
    if runtime_metadata_cache is not None:
        return runtime_metadata_cache
    worker_root = resolve_worker_root()
    if not worker_root:
        return None
    runtime_path = os.path.join(worker_root, "instance", ".firebreak-runtime.json")
    try:
        with open(runtime_path, "r", encoding="utf-8") as handle:
            runtime_metadata_cache = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None
    agent_exec_output_dir = runtime_metadata_cache.get("agent_exec_output_dir")
    if isinstance(agent_exec_output_dir, str) and agent_exec_output_dir:
        attach_stage_path_cache = os.path.join(agent_exec_output_dir, "attach_stage")
        command_signal_stream_path_cache = os.path.join(agent_exec_output_dir, "command-signals.stream")
    return runtime_metadata_cache


def current_attach_stage() -> str:
    resolve_runtime_metadata()
    if not attach_stage_path_cache:
        return ""
    try:
        return open(attach_stage_path_cache, "r", encoding="utf-8").read().strip()
    except OSError:
        return ""


def append_command_signal(signal_name: str) -> None:
    resolve_runtime_metadata()
    if not command_signal_stream_path_cache:
        return
    try:
        with open(command_signal_stream_path_cache, "a", encoding="utf-8") as handle:
            handle.write(signal_name + "\n")
    except OSError:
        pass


def command_stage_active() -> bool:
    return command_start_marker_state["seen"] or current_attach_stage() == "command-start"

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


def atomic_write_text(path: str, data: str) -> None:
    tmp_path = f"{path}.tmp-{os.getpid()}"
    try:
        with open(tmp_path, "w", encoding="utf-8") as handle:
            handle.write(data)
        os.replace(tmp_path, path)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def maybe_rewrite_firebreak_workspace(argv):
    if not argv or argv[0] != "run":
        return argv
    if not bridge_host_workspace or not bridge_guest_workspace:
        return argv

    rewritten = list(argv)
    index = 1
    while index < len(rewritten):
        arg = rewritten[index]
        workspace_value = None
        inline = False
        if arg == "--workspace":
            if index + 1 >= len(rewritten):
                break
            workspace_value = rewritten[index + 1]
        elif arg.startswith("--workspace="):
            workspace_value = arg.split("=", 1)[1]
            inline = True

        if workspace_value is not None:
            mapped = workspace_value
            if workspace_value == bridge_guest_workspace:
                mapped = bridge_host_workspace
            elif workspace_value.startswith(bridge_guest_workspace + "/"):
                mapped = bridge_host_workspace + workspace_value[len(bridge_guest_workspace):]
            if inline:
                rewritten[index] = f"--workspace={mapped}"
            else:
                rewritten[index + 1] = mapped
            break
        index += 1
    return rewritten

try:
    trace("request-loaded")
    with open(request_path, "r", encoding="utf-8") as handle:
        request = json.load(handle)
    argv = request.get("argv")
    if not isinstance(argv, list) or not argv:
        raise ValueError("request argv must be a non-empty list")
    argv = [str(item) for item in argv]
    argv = maybe_rewrite_firebreak_workspace(argv)
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
        terminal_emulation = {"owner": "bridge"}
        trace("attach-terminal-emulation:bridge")
        terminal_rows = request_lines if request_lines is not None else 24
        terminal_columns = request_columns if request_columns is not None else 80
        terminal_state = {"row": 1, "column": 1}
        terminal_query_buffer = bytearray()
        command_start_marker_state = {"seen": False, "logged": False}
        stdin_input_gate = {"open": False, "release_at": None, "saw_terminal_reply": False}
        trace_scan_state = {"offset": 0}
        focus_state = {"enabled": False, "sent": False}
        kitty_keyboard_state = {"flags": 0}
        kitty_keyboard_stack = []
        repeated_interrupt_state = {"last_at": None}
        terminal_queries = [
            (b"\x1b[6n", "cursor"),
            (b"\x1b[5n", "status"),
            (b"\x1b[?u", "kitty-kbd-query"),
            (b"\x1b[c", "da1"),
            (b"\x1b]10;?\x1b\\", "osc10"),
            (b"\x1b]10;?\x07", "osc10"),
            (b"\x1b]11;?\x1b\\", "osc11"),
            (b"\x1b]11;?\x07", "osc11"),
        ]
        sync_output_dcs_sequences = {
            b"\x1bP=1s\x1b\\": "attach-sync-output-begin",
            b"\x1bP=2s\x1b\\": "attach-sync-output-end",
        }

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

        def consume_terminal_sequence(data, index):
            if data[index] != 0x1B:
                return None, index + 1, None
            if index + 1 >= len(data):
                return None, index, "incomplete"

            next_byte = data[index + 1]
            if next_byte == 0x5B:
                seq_end = index + 2
                while seq_end < len(data) and not (0x40 <= data[seq_end] <= 0x7E):
                    seq_end += 1
                if seq_end >= len(data):
                    return None, index, "incomplete"
                return bytes(data[index:seq_end + 1]), seq_end + 1, "csi"
            if next_byte == 0x5D:
                osc_end = data.find(b"\x07", index + 2)
                st_end = data.find(b"\x1b\\", index + 2)
                candidates = [end for end in (osc_end, st_end) if end >= 0]
                if not candidates:
                    return None, index, "incomplete"
                end_index = min(candidates)
                if end_index == osc_end:
                    return bytes(data[index:end_index + 1]), end_index + 1, "osc"
                return bytes(data[index:end_index + 2]), end_index + 2, "osc"
            if next_byte == 0x50:
                dcs_end = data.find(b"\x1b\\", index + 2)
                if dcs_end < 0:
                    return None, index, "incomplete"
                return bytes(data[index:dcs_end + 2]), dcs_end + 2, "dcs"
            if next_byte == 0x1B:
                return bytes(data[index:index + 1]), index + 1, "esc"
            return bytes(data[index:index + 2]), index + 2, "esc"

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

        def parse_optional_int(raw_value, default=0):
            digits = "".join(ch for ch in raw_value if ch.isdigit())
            if not digits:
                return default
            return int(digits)

        def apply_kitty_keyboard_mode(raw_params):
            flags_raw, sep, mode_raw = raw_params.partition(";")
            flags = parse_optional_int(flags_raw, default=0)
            mode = parse_optional_int(mode_raw, default=1) if sep else 1
            previous_flags = kitty_keyboard_state["flags"]
            if mode == 1:
                kitty_keyboard_state["flags"] = flags
            elif mode == 2:
                kitty_keyboard_state["flags"] |= flags
            elif mode == 3:
                kitty_keyboard_state["flags"] &= ~flags
            trace(
                f"attach-term-kitty-set:flags={flags}:mode={mode}:previous={previous_flags}:current={kitty_keyboard_state['flags']}"
            )

        def push_kitty_keyboard_flags(raw_value):
            flags = parse_optional_int(raw_value, default=0)
            kitty_keyboard_stack.append(kitty_keyboard_state["flags"])
            kitty_keyboard_state["flags"] = flags
            trace(
                f"attach-term-kitty-push:requested={flags}:stack-depth={len(kitty_keyboard_stack)}:current={kitty_keyboard_state['flags']}"
            )

        def pop_kitty_keyboard_flags(raw_value):
            pop_count = parse_optional_int(raw_value, default=1)
            if pop_count < 1:
                pop_count = 1
            for _ in range(pop_count):
                if kitty_keyboard_stack:
                    kitty_keyboard_state["flags"] = kitty_keyboard_stack.pop()
                else:
                    kitty_keyboard_state["flags"] = 0
                    break
            trace(
                f"attach-term-kitty-pop:count={pop_count}:stack-depth={len(kitty_keyboard_stack)}:current={kitty_keyboard_state['flags']}"
            )

        def send_focus_in_event():
            if not focus_state["enabled"] or focus_state["sent"]:
                return
            try:
                write_terminal_reply(b"\x1b[I")
                trace("attach-term-reply:focus-in")
                focus_state["sent"] = True
            except OSError:
                pass

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
                        elif final == "h" and raw_params == "?1004":
                            focus_state["enabled"] = True
                            focus_state["sent"] = False
                            trace("attach-term-mode-set:?1004")
                        elif final == "l" and raw_params == "?1004":
                            focus_state["enabled"] = False
                            focus_state["sent"] = False
                            trace("attach-term-mode-reset:?1004")
                        elif final == "h":
                            trace(f"attach-term-mode-set:{raw_params or 'default'}")
                        elif final == "l":
                            trace(f"attach-term-mode-reset:{raw_params or 'default'}")
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
            if query_name == "status":
                return b"\x1b[0n"
            if query_name == "kitty-kbd-query":
                return b"\x1b[?0u"
            if query_name == "da1":
                return b"\x1b[?62;1;2;6;22c"
            if query_name == "osc10":
                return b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"
            if query_name == "osc11":
                return b"\x1b]11;rgb:0000/0000/0000\x1b\\"
            return b""

        def handle_command_start_marker():
            command_start_marker_state["seen"] = True
            terminal_emulation["owner"] = "nested"
            terminal_query_buffer.clear()
            focus_state["enabled"] = False
            focus_state["sent"] = False
            kitty_keyboard_state["flags"] = 0
            kitty_keyboard_stack.clear()
            repeated_interrupt_state["last_at"] = None
            terminal_state["row"] = 1
            terminal_state["column"] = 1
            stdin_input_gate["release_at"] = time.monotonic() + 10.0
            stdin_input_gate["saw_terminal_reply"] = False
            try:
                trace_scan_state["offset"] = os.path.getsize(trace_path)
            except OSError:
                trace_scan_state["offset"] = 0
            trace("attach-terminal-emulation:nested")
            trace("attach-command-stream-marker")

        def maybe_escalate_repeated_interrupt(chunk):
            if not command_stage_active():
                return
            now = time.monotonic()
            for byte in chunk:
                if byte != 0x03:
                    continue
                previous = repeated_interrupt_state["last_at"]
                repeated_interrupt_state["last_at"] = now
                if previous is None or now - previous > 8.0:
                    continue
                append_command_signal("INT")
                trace("attach-signal-request:INT")

        def note_nested_terminal_replies():
            if stdin_input_gate["saw_terminal_reply"]:
                return
            try:
                with open(trace_path, "r", encoding="utf-8") as handle:
                    handle.seek(trace_scan_state["offset"])
                    lines = handle.readlines()
                    trace_scan_state["offset"] = handle.tell()
            except OSError:
                return
            for line in lines:
                if not line.startswith("attach-term-reply:"):
                    continue
                stdin_input_gate["saw_terminal_reply"] = True
                trace("attach-stdin-gate-arm:trace-terminal-reply")
                return

        def handle_terminal_queries(chunk):
            if terminal_emulation["owner"] == "nested":
                update_terminal_cursor(chunk)
                return chunk

            terminal_query_buffer.extend(chunk)
            data = bytes(terminal_query_buffer)
            forwarded = bytearray()
            index = 0

            while index < len(data):
                if data[index] == 0x1B:
                    sequence, next_index, sequence_type = consume_terminal_sequence(data, index)
                    if sequence_type == "incomplete":
                        break
                    if sequence_type == "dcs" and sequence in sync_output_dcs_sequences:
                        trace(sync_output_dcs_sequences[sequence])
                        index = next_index
                        continue
                    if sequence_type == "csi" and sequence is not None:
                        raw_params = sequence[2:-1].decode("ascii", "ignore")
                        final = chr(sequence[-1])
                        if final == "u":
                            if raw_params.startswith(">"):
                                push_kitty_keyboard_flags(raw_params[1:])
                                index = next_index
                                continue
                            if raw_params.startswith("<"):
                                pop_kitty_keyboard_flags(raw_params[1:])
                                index = next_index
                                continue
                            if raw_params.startswith("="):
                                apply_kitty_keyboard_mode(raw_params[1:])
                                index = next_index
                                continue
                        if raw_params == "?2026" and final == "h":
                            trace("attach-term-mode-set:?2026")
                            index = next_index
                            continue
                        if raw_params == "?2026" and final == "l":
                            trace("attach-term-mode-reset:?2026")
                            index = next_index
                            continue
                    matched_query = False
                    if sequence is not None:
                        for pattern, query_name in terminal_queries:
                            if sequence != pattern:
                                continue
                            trace(f"attach-term-query:{query_name}")
                            response = build_terminal_reply(query_name)
                            try:
                                write_terminal_reply(response)
                                trace(f"attach-term-reply:{query_name}:{response.hex()}")
                            except OSError:
                                pass
                            index = next_index
                            matched_query = True
                            break
                    if matched_query:
                        continue
                    if sequence is not None:
                        forwarded.extend(sequence)
                        update_terminal_cursor(sequence)
                        index = next_index
                        continue

                byte = data[index:index + 1]
                forwarded.extend(byte)
                update_terminal_cursor(byte)
                index += 1

            terminal_query_buffer[:] = data[index:]

            return bytes(forwarded)

        def pump_stdin():
            offset = 0
            pending_input = bytearray()
            saw_input = False
            total_input_bytes = 0
            sample_budget = 64
            try:
                trace("attach-stdin-stream-opened")
                while True:
                    if command_start_marker_state["seen"] and not command_start_marker_state["logged"]:
                        trace(f"attach-stdin-command-start:pending={len(pending_input)}")
                        command_start_marker_state["logged"] = True
                    if command_start_marker_state["seen"] and not stdin_input_gate["open"]:
                        note_nested_terminal_replies()
                    if (
                        command_start_marker_state["seen"]
                        and pending_input
                        and (
                            stdin_input_gate["open"]
                            or (
                                stdin_input_gate["release_at"] is not None
                                and time.monotonic() >= stdin_input_gate["release_at"]
                            )
                        )
                    ):
                        if not stdin_input_gate["open"]:
                            stdin_input_gate["open"] = True
                            trace("attach-stdin-gate-open:timeout")
                        chunk = bytes(pending_input)
                        pending_input.clear()
                        maybe_escalate_repeated_interrupt(chunk)
                        os.write(master_fd, chunk)
                    with open(stdin_stream, "rb") as source:
                        source.seek(offset)
                        chunk = source.read(4096)
                    if chunk:
                        offset += len(chunk)
                        total_input_bytes += len(chunk)
                        if not saw_input:
                            trace("attach-stdin-first-byte")
                            trace(f"attach-stdin-first-chunk-len:{len(chunk)}")
                            saw_input = True
                        if sample_budget > 0:
                            sample = chunk[:sample_budget]
                            trace(f"attach-stdin-sample-len:{len(sample)}")
                            sample_budget -= len(sample)
                        if (
                            not command_start_marker_state["seen"]
                            or (
                                not stdin_input_gate["open"]
                                and stdin_input_gate["release_at"] is not None
                                and time.monotonic() < stdin_input_gate["release_at"]
                            )
                        ):
                            pending_input.extend(chunk)
                            continue
                        maybe_escalate_repeated_interrupt(chunk)
                        os.write(master_fd, chunk)
                        continue
                    if os.path.exists(stdin_eof_path):
                        trace("attach-stdin-eof")
                        break
                    time.sleep(poll_interval)
            except OSError:
                pass
            finally:
                if saw_input:
                    trace(f"attach-stdin-total-bytes:{total_input_bytes}")

        def pump_stdout():
            saw_output = False
            command_stage_initialized = False
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
                        command_start_marker_seen_before_chunk = command_start_marker_state["seen"]
                        if current_attach_stage() == "command-start" and not command_start_marker_state["seen"]:
                            handle_command_start_marker()
                        if command_start_marker_state["seen"] and not stdin_input_gate["open"]:
                            note_nested_terminal_replies()
                        if not command_stage_initialized and (command_start_marker_state["seen"] or current_attach_stage() == "command-start"):
                            command_stage_initialized = True
                        if (
                            command_start_marker_seen_before_chunk
                            and stdin_input_gate["saw_terminal_reply"]
                            and not stdin_input_gate["open"]
                            and (b"\n" in chunk or b"\r" in chunk)
                        ):
                            stdin_input_gate["open"] = True
                            trace("attach-stdin-gate-open:stdout-line")
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
        try:
            os.close(master_fd)
        except OSError:
            pass
        stdin_thread.join(timeout=1)
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

# response.exit-code is the commit signal: response.stdout and response.stderr must be complete first.
atomic_write_text(stdout_path, stdout)
atomic_write_text(stderr_path, stderr)
atomic_write_text(exit_code_path, f"{exit_code}\n")
persist_response_exit_code(exit_code)
trace("response-written")
PY
  request_status=$?
  rm -rf "$lock_dir"
  return "$request_status"
}

request_lock_active() {
  lock_dir=$1
  [ -d "$lock_dir" ] || return 1
  [ -r "$lock_dir/pid" ] || return 1

  IFS= read -r lock_pid <"$lock_dir/pid" || lock_pid=""
  case "$lock_pid" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac

  kill -0 "$lock_pid" 2>/dev/null
}

while :; do
  for request_dir in "$bridge_dir"/requests/*; do
    [ -d "$request_dir" ] || continue
    [ -f "$request_dir/response.exit-code" ] && continue
    if request_lock_active "$request_dir/.lock"; then
      continue
    fi
    process_request "$request_dir" &
  done
  sleep "$poll_interval"
done
