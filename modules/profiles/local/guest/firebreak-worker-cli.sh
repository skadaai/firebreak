set -eu

bridge_dir=@WORKER_BRIDGE_MOUNT@
worker_kinds_file=@WORKER_KINDS_FILE@
local_helper=@WORKER_LOCAL_HELPER@
local_state_dir=@WORKER_LOCAL_STATE_DIR@
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak worker run --kind KIND [--workspace PATH] [--backend BACKEND] [--package NAME] [--launch-mode MODE] [--attach] [--json] [--] COMMAND...
  firebreak worker ps [-a|--all] [--json]
  firebreak worker inspect WORKER_ID
  firebreak worker logs [--stdout|--stderr] [-f|--follow] WORKER_ID
  firebreak worker debug [--json]
  firebreak worker stop [--all] [--json] [WORKER_ID...]
  firebreak worker rm [--all] [--force] [--json] [WORKER_ID...]
  firebreak worker prune [--force] [--json]
EOF
  exit "${1:-1}"
}

bridge_request() {
  if ! [ -d "$bridge_dir" ]; then
    echo "Firebreak worker bridge is unavailable at $bridge_dir" >&2
    exit 1
  fi

  requests_dir=$bridge_dir/requests
  mkdir -p "$requests_dir"
  request_dir=$(mktemp -d "$requests_dir/request.XXXXXX")
  request_tmp_path=$request_dir/request.json.tmp

  REQUEST_PATH=$request_tmp_path python3 - "$@" <<'PY'
import json
import os
import sys

request_path = os.environ["REQUEST_PATH"]
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump({"argv": sys.argv[1:]}, handle)
PY
  mv "$request_tmp_path" "$request_dir/request.json"

  for _ in $(seq 1 600); do
    if [ -f "$request_dir/response.exit-code" ]; then
      break
    fi
    sleep 0.1
  done

  if ! [ -f "$request_dir/response.exit-code" ]; then
    echo "timed out waiting for Firebreak worker bridge response" >&2
    exit 1
  fi

  if [ -f "$request_dir/response.stdout" ]; then
    cat "$request_dir/response.stdout"
  fi
  if [ -f "$request_dir/response.stderr" ]; then
    cat "$request_dir/response.stderr" >&2
  fi

  IFS= read -r bridge_exit_code < "$request_dir/response.exit-code" || bridge_exit_code=1
  case "$bridge_exit_code" in
    ''|*[!0-9]*)
      echo "invalid Firebreak worker bridge exit code: $bridge_exit_code" >&2
      exit 1
      ;;
  esac
  return "$bridge_exit_code"
}

bridge_request_attach() {
  if ! [ -d "$bridge_dir" ]; then
    echo "Firebreak worker bridge is unavailable at $bridge_dir" >&2
    exit 1
  fi

  requests_dir=$bridge_dir/requests
  printf '%s\n' 'firebreak: connecting to worker bridge' >&2
  mkdir -p "$requests_dir"
  request_dir=$(mktemp -d "$requests_dir/request.XXXXXX")
  request_tmp_path=$request_dir/request.json.tmp
  interactive_mode=0
  if [ -t 0 ] && [ -t 1 ]; then
    interactive_mode=1
  fi

  if [ "$interactive_mode" = "1" ]; then
    stdin_stream=$request_dir/stdin.stream
    stdout_stream=$request_dir/stdout.stream
    : >"$stdin_stream"
    : >"$stdout_stream"
  fi

  request_term=${TERM:-}
  request_columns=${COLUMNS:-}
  request_lines=${LINES:-}
  case "$request_columns" in
    ''|*[!0-9]*|0)
      request_columns=""
      ;;
  esac
  case "$request_lines" in
    ''|*[!0-9]*|0)
      request_lines=""
      ;;
  esac
  if [ "$interactive_mode" = "1" ]; then
    stty_size=$(stty size 2>/dev/null || true)
    if [ -n "$stty_size" ]; then
      stty_lines=${stty_size%% *}
      stty_columns=${stty_size##* }
      case "$stty_lines" in
        ''|*[!0-9]*|0)
          stty_lines=""
          ;;
      esac
      case "$stty_columns" in
        ''|*[!0-9]*|0)
          stty_columns=""
          ;;
      esac
      if [ -n "$stty_lines" ] && [ -n "$stty_columns" ]; then
        request_lines=$stty_lines
        request_columns=$stty_columns
      fi
    fi
  fi

  REQUEST_PATH=$request_tmp_path INTERACTIVE_MODE=$interactive_mode REQUEST_TERM=$request_term REQUEST_COLUMNS=$request_columns REQUEST_LINES=$request_lines python3 - "$@" <<'PY'
import json
import os
import sys

request_path = os.environ["REQUEST_PATH"]
interactive = os.environ["INTERACTIVE_MODE"] == "1"
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "argv": sys.argv[1:],
            "attach": True,
            "interactive": interactive,
            "term": os.environ.get("REQUEST_TERM", ""),
            "columns": os.environ.get("REQUEST_COLUMNS", ""),
            "lines": os.environ.get("REQUEST_LINES", ""),
        },
        handle,
    )
PY

  if [ "$interactive_mode" != "1" ]; then
    mv "$request_tmp_path" "$request_dir/request.json"

    for _ in $(seq 1 36000); do
      if [ -f "$request_dir/response.exit-code" ]; then
        break
      fi
      sleep 0.1
    done

    if ! [ -f "$request_dir/response.exit-code" ]; then
      echo "timed out waiting for Firebreak worker attach response" >&2
      exit 1
    fi

    if [ -f "$request_dir/response.stdout" ]; then
      cat "$request_dir/response.stdout"
    fi
    if [ -f "$request_dir/response.stderr" ]; then
      cat "$request_dir/response.stderr" >&2
    fi

    IFS= read -r bridge_exit_code < "$request_dir/response.exit-code" || bridge_exit_code=1
    case "$bridge_exit_code" in
      ''|*[!0-9]*)
        echo "invalid Firebreak worker bridge exit code: $bridge_exit_code" >&2
        exit 1
        ;;
    esac
    return "$bridge_exit_code"
  fi

  tty_state=""
  tty_state=$(stty -g)
  stty raw -echo

  restore_tty() {
    if [ -n "$tty_state" ]; then
      stty "$tty_state" 2>/dev/null || true
    fi
  }

  reset_attach_terminal_ui() {
    if [ -e /dev/tty ]; then
      printf '\r\033[2K\033[0m\033[r\033[?25h\033[?1049l\033[?1047l\033[?1048l\033[?2004l\033[?1004l\033[?1006l\033[?1003l\033[?1002l\033[?1000l\033[?2026l\n' >/dev/tty 2>/dev/null || true
    fi
  }

  cleanup_attach() {
    release_kind_spawn_lock
    restore_tty
  }

  trap cleanup_attach EXIT INT TERM

  mv "$request_tmp_path" "$request_dir/request.json"
  printf '%s\n' 'firebreak: starting worker' >&2
  attach_client_script=$request_dir/attach-client.py
  cat >"$attach_client_script" <<'PY'
import os
import select
import sys
import threading
import time
import errno
import fcntl

request_dir = os.environ["REQUEST_DIR"]
stdin_stream = os.environ["STDIN_STREAM"]
stdout_stream = os.environ["STDOUT_STREAM"]
exit_code_path = os.path.join(request_dir, "response.exit-code")
trace_path = os.path.join(request_dir, "trace.log")
stdin_fd = sys.stdin.fileno()
stdout_fd = sys.stdout.fileno()
stderr_fd = sys.stderr.fileno()

input_fd = stdin_fd
input_fd_is_tty = os.isatty(stdin_fd)

stdout_done = threading.Event()
stdout_started = threading.Event()
progress_done = threading.Event()
stdin_done = threading.Event()
printed_messages = set()
poll_interval = 0.005
stdin_reply_buffer = bytearray()
stdout_flags = fcntl.fcntl(stdout_fd, fcntl.F_GETFL)
fcntl.fcntl(stdout_fd, fcntl.F_SETFL, stdout_flags | os.O_NONBLOCK)


def trace(message: str) -> None:
    try:
        with open(trace_path, "a", encoding="utf-8") as handle:
            handle.write(message + "\n")
    except OSError:
        pass


def print_progress(message: str) -> None:
    if message in printed_messages:
        return
    printed_messages.add(message)
    os.write(stderr_fd, (message + "\n").encode())


def classify_csi_reply(sequence: bytes):
    if not sequence.startswith(b"\x1b[") or len(sequence) < 3:
        return None
    final = sequence[-1:]
    payload = sequence[2:-1].decode("ascii", "ignore")
    if final == b"R":
        parts = payload.split(";")
        if len(parts) == 2 and all(part.isdigit() for part in parts):
            return "cursor"
    if payload.startswith("?") and final == b"u":
        reply_body = payload[1:]
        if reply_body and all(ch.isdigit() or ch in ";:" for ch in reply_body):
            return "kitty-kbd-reply"
    if payload.startswith("?") and final == b"c":
        reply_body = payload[1:]
        if reply_body and all(ch.isdigit() or ch in ";:" for ch in reply_body):
            return "da1-reply"
    return None


def classify_osc_reply(sequence: bytes):
    if sequence.startswith(b"\x1b]10;"):
        return "osc10-reply"
    if sequence.startswith(b"\x1b]11;"):
        return "osc11-reply"
    return None


def is_partial_reply(data: bytes) -> bool:
    if not data:
        return False
    if data == b"\x1b":
        return True
    if data.startswith(b"\x1b]"):
        return data.startswith((b"\x1b]10;", b"\x1b]11;"))
    if not data.startswith(b"\x1b["):
        return False
    if len(data) == 2:
        return True
    payload = data[2:]
    return all(byte in b"0123456789;:?" for byte in payload)


def strip_terminal_replies(chunk: bytes) -> bytes:
    stdin_reply_buffer.extend(chunk)
    data = bytes(stdin_reply_buffer)
    forwarded = bytearray()
    index = 0

    while index < len(data):
        byte = data[index]
        if byte != 0x1B:
            forwarded.append(byte)
            index += 1
            continue

        if index + 1 >= len(data):
            break

        next_byte = data[index + 1]
        if next_byte == 0x5B:
            seq_end = index + 2
            while seq_end < len(data) and not (0x40 <= data[seq_end] <= 0x7E):
                seq_end += 1
            if seq_end >= len(data):
                break
            sequence = data[index:seq_end + 1]
            reply_name = classify_csi_reply(sequence)
            if reply_name is not None:
                trace(f"guest-stdin-term-reply:{reply_name}:{sequence.hex()}")
                index = seq_end + 1
                continue
            forwarded.extend(sequence)
            index = seq_end + 1
            continue

        if next_byte == 0x5D:
            osc_end_bel = data.find(b"\x07", index + 2)
            osc_end_st = data.find(b"\x1b\\", index + 2)
            end_candidates = [end for end in (osc_end_bel, osc_end_st) if end >= 0]
            if not end_candidates:
                break
            end_index = min(end_candidates)
            if end_index == osc_end_bel:
                sequence = data[index:end_index + 1]
                advance = end_index + 1
            else:
                sequence = data[index:end_index + 2]
                advance = end_index + 2
            reply_name = classify_osc_reply(sequence)
            if reply_name is not None:
                trace(f"guest-stdin-term-reply:{reply_name}:{sequence.hex()}")
                index = advance
                continue
            forwarded.extend(sequence)
            index = advance
            continue

        forwarded.append(byte)
        index += 1

    remainder = data[index:]
    if remainder and not is_partial_reply(remainder):
        forwarded.extend(remainder)
        stdin_reply_buffer.clear()
    else:
        stdin_reply_buffer[:] = remainder

    return bytes(forwarded)


def pump_stdout() -> None:
    offset = 0
    pending = bytearray()
    saw_stdout_bytes = False
    total_stdout_bytes = 0
    pending_high_water = 0
    last_block_trace_at = 0.0
    try:
        while True:
            current_size = 0
            if os.path.exists(stdout_stream):
                try:
                    current_size = os.path.getsize(stdout_stream)
                except OSError:
                    current_size = 0
            if current_size > offset and len(pending) < 262144:
                with open(stdout_stream, "rb") as handle:
                    handle.seek(offset)
                    chunk = handle.read(min(65536, current_size - offset))
                if chunk:
                    offset += len(chunk)
                    pending.extend(chunk)
                    if len(pending) > pending_high_water:
                        pending_high_water = len(pending)
            if pending:
                stdout_started.set()
                _, writable, _ = select.select([], [stdout_fd], [], poll_interval)
                if not writable:
                    now = time.monotonic()
                    if now - last_block_trace_at >= 1.0:
                        trace(f"guest-stdout-backpressure:pending={len(pending)}")
                        last_block_trace_at = now
                    continue
                try:
                    written = os.write(stdout_fd, pending)
                except BlockingIOError:
                    continue
                except OSError as error:
                    if error.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        continue
                    trace(f"guest-stdout-write-error:{error.errno}")
                    break
                if written > 0:
                    if not saw_stdout_bytes:
                        trace("guest-stdout-first-byte")
                        saw_stdout_bytes = True
                    total_stdout_bytes += written
                    del pending[:written]
                    continue
            if os.path.exists(exit_code_path) and not pending and offset >= current_size:
                break
            time.sleep(poll_interval)
    finally:
        if saw_stdout_bytes:
            trace(f"guest-stdout-total-bytes:{total_stdout_bytes}")
        trace(f"guest-stdout-pending-high-water:{pending_high_water}")
        stdout_done.set()


def pump_stdin() -> None:
    saw_stdin_bytes = False
    total_stdin_bytes = 0
    sample_budget = 64
    try:
        trace(f"guest-stdin-source:{'tty' if input_fd_is_tty else 'stdin'}")
        with open(stdin_stream, "ab", buffering=0) as sink:
            while True:
                if os.path.exists(exit_code_path):
                    break
                readable, _, _ = select.select([input_fd], [], [], poll_interval)
                if not readable:
                    continue
                chunk = os.read(input_fd, 4096)
                if not chunk:
                    if saw_stdin_bytes:
                        trace("guest-stdin-eof-after-bytes")
                        eof_marker = os.path.join(request_dir, "stdin.eof")
                        with open(eof_marker, "w", encoding="utf-8"):
                            pass
                        break
                    trace("guest-stdin-empty-before-bytes")
                    break
                chunk = strip_terminal_replies(chunk)
                if not chunk:
                    continue
                if not saw_stdin_bytes:
                    trace("guest-stdin-first-byte")
                    trace(f"guest-stdin-first-chunk-hex:{chunk[:32].hex()}")
                saw_stdin_bytes = True
                total_stdin_bytes += len(chunk)
                if sample_budget > 0:
                    sample = chunk[:sample_budget]
                    trace(f"guest-stdin-sample-hex:{sample.hex()}")
                    sample_budget -= len(sample)
                sink.write(chunk)
                sink.flush()
    finally:
        if saw_stdin_bytes:
            trace(f"guest-stdin-total-bytes:{total_stdin_bytes}")
        stdin_done.set()


def pump_progress() -> None:
    seen_trace_lines = 0
    reminded = False
    started_at = time.monotonic()
    while not progress_done.is_set():
        if os.path.exists(trace_path):
            try:
                with open(trace_path, "r", encoding="utf-8") as handle:
                    trace_lines = [line.strip() for line in handle if line.strip()]
            except OSError:
                trace_lines = []
            if seen_trace_lines < len(trace_lines):
                for line in trace_lines[seen_trace_lines:]:
                    if line == "request-loaded":
                        print_progress("firebreak: request accepted")
                    elif line == "attach-pty-open":
                        print_progress("firebreak: attaching terminal")
                    elif line == "attach-worker-started":
                        print_progress("firebreak: worker started, waiting for output")
                    elif line == "attach-stdout-first-byte":
                        print_progress("firebreak: worker produced terminal output")
                    elif line == "attach-stdout-eof":
                        print_progress("firebreak: worker terminal output closed")
                    elif line == "attach-waitpid-returned":
                        print_progress("firebreak: worker process exited")
                    elif line.startswith("attach-worker-exit:"):
                        print_progress(f"firebreak: worker exited ({line.split(':', 1)[1]})")
                    elif line == "response-written":
                        print_progress("firebreak: attach session completed")
                seen_trace_lines = len(trace_lines)
        if stdout_started.is_set() or os.path.exists(exit_code_path):
            break
        if not reminded and time.monotonic() - started_at >= 15:
            print_progress("firebreak: still waiting for worker output")
            reminded = True
        time.sleep(0.05)

stdout_thread = threading.Thread(target=pump_stdout, daemon=True)
stdin_thread = threading.Thread(target=pump_stdin, daemon=True)
progress_thread = threading.Thread(target=pump_progress, daemon=True)
stdout_thread.start()
stdin_thread.start()
progress_thread.start()

while not os.path.exists(exit_code_path) and not stdout_done.is_set():
    stdout_thread.join(timeout=poll_interval)

trace("guest-attach-client-main-loop-exit")
progress_done.set()
stdout_done.set()
stdin_done.set()
stdout_thread.join(timeout=2)
trace(f"guest-attach-client-stdout-thread-alive:{stdout_thread.is_alive()}")
stdin_thread.join(timeout=1)
trace(f"guest-attach-client-stdin-thread-alive:{stdin_thread.is_alive()}")
progress_thread.join(timeout=1)
trace(f"guest-attach-client-progress-thread-alive:{progress_thread.is_alive()}")

try:
    pass
except Exception:
    pass
PY
  chmod 0555 "$attach_client_script"
  REQUEST_DIR=$request_dir STDIN_STREAM=$stdin_stream STDOUT_STREAM=$stdout_stream python3 "$attach_client_script"

  cleanup_attach
  trap - EXIT INT TERM

  if ! [ -f "$request_dir/response.exit-code" ]; then
    echo "timed out waiting for Firebreak worker attach response" >&2
    exit 1
  fi

  IFS= read -r bridge_exit_code < "$request_dir/response.exit-code" || bridge_exit_code=1
  restore_tty
  reset_attach_terminal_ui
  case "$bridge_exit_code" in
    ''|*[!0-9]*)
      echo "invalid Firebreak worker bridge exit code: $bridge_exit_code" >&2
      exit 1
      ;;
  esac
  return "$bridge_exit_code"
}

resolve_kind() {
  kind_name=$1
  [ -r "$worker_kinds_file" ] || {
    echo "Firebreak worker kinds file is unavailable: $worker_kinds_file" >&2
    exit 1
  }

  KIND_NAME=$kind_name WORKER_KINDS_FILE=$worker_kinds_file python3 - <<'PY'
import json
import os
import sys

kind_name = os.environ["KIND_NAME"]
with open(os.environ["WORKER_KINDS_FILE"], "r", encoding="utf-8") as handle:
    kinds = json.load(handle)

if kind_name not in kinds:
    print(f"unknown worker kind: {kind_name}", file=sys.stderr)
    sys.exit(1)

print(json.dumps(kinds[kind_name]))
PY
}

resolve_kind_field() {
  kind_json=$1
  field_name=$2

  KIND_JSON=$kind_json FIELD_NAME=$field_name python3 - <<'PY'
import json
import os

data = json.loads(os.environ["KIND_JSON"])
value = data.get(os.environ["FIELD_NAME"])
if value is None:
    print("")
elif isinstance(value, str):
    print(value)
else:
    print(json.dumps(value))
PY
}

merge_arrays() {
  local_json=$1
  bridge_json=$2
  LOCAL_JSON=$local_json BRIDGE_JSON=$bridge_json python3 - <<'PY'
import json
import os

local_items = json.loads(os.environ["LOCAL_JSON"])
bridge_items = json.loads(os.environ["BRIDGE_JSON"])
print(json.dumps(local_items + bridge_items, indent=2))
PY
}

append_json_item() {
  base_json=$1
  item_json=$2
  BASE_JSON=$base_json ITEM_JSON=$item_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["BASE_JSON"])
item = json.loads(os.environ["ITEM_JSON"])
items.append(item)
print(json.dumps(items))
PY
}

print_worker_ids() {
  json_input=$1
  JSON_INPUT=$json_input python3 - <<'PY'
import json
import os

value = json.loads(os.environ["JSON_INPUT"])
if isinstance(value, dict):
    worker_id = value.get("worker_id")
    if worker_id:
        print(worker_id)
else:
    for item in value:
        worker_id = item.get("worker_id")
        if worker_id:
            print(worker_id)
PY
}

print_ps_table() {
  json_input=$1
  JSON_INPUT=$json_input python3 - <<'PY'
import json
import os

items = json.loads(os.environ["JSON_INPUT"])
print(f"{'WORKER ID':<22} {'KIND':<14} {'BACKEND':<10} {'STATUS':<10} {'EXIT':<6}")
for item in items:
    exit_code = item.get("exit_code")
    print(f"{item.get('worker_id',''):<22} {item.get('kind',''):<14} {item.get('backend',''):<10} {item.get('status',''):<10} {('-' if exit_code is None else exit_code)!s:<6}")
PY
}

bridge_ps_json() {
  if ! [ -d "$bridge_dir" ]; then
    printf '%s\n' '[]'
    return 0
  fi

  if [ "${1:-}" = "--all" ]; then
    bridge_request ps --all --json
  else
    bridge_request ps --json
  fi
}

resolve_kind_max_instances() {
  kind_json=$1

  KIND_JSON=$kind_json python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["KIND_JSON"])
value = data.get("max_instances", data.get("maxInstances"))

if value is None or value == "":
    print("")
    raise SystemExit(0)

if isinstance(value, int):
    parsed = value
elif isinstance(value, str) and value.isdigit():
    parsed = int(value)
else:
    print("worker kind max_instances must be a positive integer", file=sys.stderr)
    raise SystemExit(1)

if parsed <= 0:
    print("worker kind max_instances must be greater than zero", file=sys.stderr)
    raise SystemExit(1)

print(parsed)
PY
}

count_active_workers_for_kind() {
  kind_name=$1
  kind_backend=$2

  case "$kind_backend" in
    process)
      local_json=$("$local_helper" ps --all --json)
      bridge_json='[]'
      ;;
    firebreak)
      local_json='[]'
      bridge_json=$(bridge_ps_json --all)
      ;;
    *)
      local_json=$("$local_helper" ps --all --json)
      bridge_json=$(bridge_ps_json --all)
      ;;
  esac

  KIND_NAME=$kind_name LOCAL_JSON=$local_json BRIDGE_JSON=$bridge_json python3 - <<'PY'
import json
import os

kind_name = os.environ["KIND_NAME"]
active_statuses = {"active", "created", "running", "stopping"}
items = json.loads(os.environ["LOCAL_JSON"]) + json.loads(os.environ["BRIDGE_JSON"])
count = 0

for item in items:
    if item.get("kind") != kind_name:
        continue
    if item.get("status") in active_statuses:
        count += 1

print(count)
PY
}

enforce_kind_limit() {
  kind_json=$1
  kind_name=$2
  kind_backend=$3

  max_instances=$(resolve_kind_max_instances "$kind_json")
  if [ -z "$max_instances" ]; then
    return 0
  fi

  active_count=$(count_active_workers_for_kind "$kind_name" "$kind_backend")
  if [ "$active_count" -ge "$max_instances" ]; then
    echo "worker kind '$kind_name' reached max_instances=$max_instances" >&2
    exit 1
  fi
}

local_worker_exists() {
  worker_id=$1
  [ -f "$local_state_dir/workers/$worker_id/metadata.json" ]
}

acquire_kind_spawn_lock() {
  kind_name=$1
  lock_root=$local_state_dir/spawn-locks
  kind_spawn_lock_dir=$lock_root/$kind_name.lock
  current_boot_id=""

  if [ -r /proc/sys/kernel/random/boot_id ]; then
    IFS= read -r current_boot_id </proc/sys/kernel/random/boot_id || current_boot_id=""
  fi

  mkdir -p "$lock_root"
  while :; do
    if mkdir "$kind_spawn_lock_dir" 2>/dev/null; then
      printf '%s\n' "$$" >"$kind_spawn_lock_dir/pid"
      if [ -n "$current_boot_id" ]; then
        printf '%s\n' "$current_boot_id" >"$kind_spawn_lock_dir/boot-id"
      fi
      date +%s >"$kind_spawn_lock_dir/acquired-at"
      return 0
    fi

    stale_lock_pid=""
    stale_lock_boot_id=""
    if [ -r "$kind_spawn_lock_dir/pid" ]; then
      IFS= read -r stale_lock_pid <"$kind_spawn_lock_dir/pid" || stale_lock_pid=""
    fi
    if [ -r "$kind_spawn_lock_dir/boot-id" ]; then
      IFS= read -r stale_lock_boot_id <"$kind_spawn_lock_dir/boot-id" || stale_lock_boot_id=""
    fi

    if [ -n "$current_boot_id" ] && [ -z "$stale_lock_boot_id" ]; then
      rm -rf "$kind_spawn_lock_dir"
      continue
    fi

    if [ -n "$current_boot_id" ] && [ -n "$stale_lock_boot_id" ] && [ "$stale_lock_boot_id" != "$current_boot_id" ]; then
      rm -rf "$kind_spawn_lock_dir"
      continue
    fi

    if [ -n "$stale_lock_pid" ] && ! kill -0 "$stale_lock_pid" 2>/dev/null; then
      rm -rf "$kind_spawn_lock_dir"
      continue
    fi

    sleep 0.1
  done
}

release_kind_spawn_lock() {
  if [ -n "${kind_spawn_lock_dir:-}" ]; then
    rm -f "$kind_spawn_lock_dir/pid" "$kind_spawn_lock_dir/boot-id" "$kind_spawn_lock_dir/acquired-at"
    rmdir "$kind_spawn_lock_dir" 2>/dev/null || true
    kind_spawn_lock_dir=""
  fi
}

collect_json_results_for_ids() {
  action=$1
  shift
  action_args=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    action_args+=("$1")
    shift
  done
  if [ "${1:-}" = "--" ]; then
    shift
  fi

  json_output='[]'
  for worker_id in "$@"; do
    if local_worker_exists "$worker_id"; then
      item_json=$("$local_helper" "$action" "${action_args[@]}" --json "$worker_id")
    else
      item_json=$(bridge_request "$action" "${action_args[@]}" --json "$worker_id")
    fi
    json_output=$(append_json_item "$json_output" "$item_json")
  done
  printf '%s\n' "$json_output"
}

case "$command" in
  worker)
    shift
    ;;
  ""|help|-h|--help)
    usage 0
    ;;
  *)
    echo "unsupported guest firebreak command: $command" >&2
    usage 1
    ;;
esac

subcommand=${1:-}
case "$subcommand" in
  run)
    shift
    attach_mode=0
    backend=""
    kind=""
    workspace=$PWD
    package_name=""
    launch_mode=""
    run_json=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --backend)
          backend=$2
          shift 2
          ;;
        --kind)
          kind=$2
          shift 2
          ;;
        --workspace)
          workspace=$2
          shift 2
          ;;
        --package)
          package_name=$2
          shift 2
          ;;
        --launch-mode)
          launch_mode=$2
          shift 2
          ;;
        --json)
          run_json=1
          shift
          ;;
        --attach)
          attach_mode=1
          shift
          ;;
        --)
          shift
          break
          ;;
        -*)
          usage
          ;;
        *)
          break
          ;;
      esac
    done

    [ -n "$kind" ] || usage
    if [ "$attach_mode" = "1" ]; then
      printf '%s\n' "firebreak: resolving worker kind ($kind)" >&2
    fi
    kind_json=$(resolve_kind "$kind")

    if [ -z "$backend" ]; then
      backend=$(resolve_kind_field "$kind_json" "backend")
    fi

    if [ "$attach_mode" = "1" ] && [ "$run_json" = "1" ]; then
      echo "firebreak worker run does not support --attach with --json" >&2
      exit 1
    fi

    case "$backend" in
      process|firebreak) ;;
      *)
        echo "unsupported worker backend: $backend" >&2
        exit 1
        ;;
    esac

    if [ "$attach_mode" = "1" ]; then
      printf '%s\n' "firebreak: acquiring worker slot ($kind)" >&2
    fi
    acquire_kind_spawn_lock "$kind"
    if [ "$attach_mode" = "1" ]; then
      printf '%s\n' "firebreak: worker slot acquired ($kind)" >&2
    fi
    trap release_kind_spawn_lock EXIT INT TERM
    enforce_kind_limit "$kind_json" "$kind" "$backend"
    if [ "$attach_mode" = "1" ]; then
      printf '%s\n' "firebreak: worker slot validated ($kind)" >&2
    fi

    case "$backend" in
      process)
        if [ "$#" -eq 0 ]; then
          default_command_json=$(resolve_kind_field "$kind_json" "command")
          if [ -n "$default_command_json" ]; then
            KIND_JSON=$kind_json WORKER_LOCAL_HELPER=$local_helper WORKER_KIND=$kind WORKER_WORKSPACE=$workspace WORKER_RUN_JSON=$run_json WORKER_ATTACH_MODE=$attach_mode python3 - <<'PY'
import json
import os
import subprocess
import sys

data = json.loads(os.environ["KIND_JSON"])
command = data.get("command")
if not isinstance(command, list) or not command:
    raise SystemExit(0)

argv = [
    os.environ["WORKER_LOCAL_HELPER"],
    "run",
    "--backend",
    "process",
    "--kind",
    os.environ["WORKER_KIND"],
    "--workspace",
    os.environ["WORKER_WORKSPACE"],
]
if os.environ.get("WORKER_ATTACH_MODE") == "1":
    argv.append("--attach")
if os.environ["WORKER_RUN_JSON"] == "1":
    argv.append("--json")
argv.extend(["--", *[str(item) for item in command]])
result = subprocess.run(argv, check=False)
sys.exit(result.returncode)
PY
            run_status=$?
            release_kind_spawn_lock
            trap - EXIT INT TERM
            exit "$run_status"
          fi
        fi
        if [ "$attach_mode" = "1" ]; then
          "$local_helper" run --backend process --kind "$kind" --workspace "$workspace" --attach -- "$@"
        elif [ "$run_json" = "1" ]; then
          "$local_helper" run --backend process --kind "$kind" --workspace "$workspace" --json -- "$@"
        else
          "$local_helper" run --backend process --kind "$kind" --workspace "$workspace" -- "$@"
        fi
        run_status=$?
        release_kind_spawn_lock
        trap - EXIT INT TERM
        exit "$run_status"
        ;;
      firebreak)
        if [ -z "$package_name" ]; then
          package_name=$(resolve_kind_field "$kind_json" "package")
        fi
        if [ -z "$launch_mode" ]; then
          launch_mode=$(resolve_kind_field "$kind_json" "launch_mode")
        fi
        if [ -z "$launch_mode" ]; then
          launch_mode=run
        fi
        if [ "$attach_mode" = "1" ]; then
          bridge_request_attach run --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --launch-mode "$launch_mode" --attach -- "$@"
        elif [ "$run_json" = "1" ]; then
          bridge_request run --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --launch-mode "$launch_mode" --json -- "$@"
        else
          bridge_request run --backend firebreak --kind "$kind" --workspace "$workspace" --package "$package_name" --launch-mode "$launch_mode" -- "$@"
        fi
        run_status=$?
        release_kind_spawn_lock
        trap - EXIT INT TERM
        exit "$run_status"
        ;;
    esac
    ;;
  ps)
    shift
    ps_all=0
    ps_json=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -a|--all)
          ps_all=1
          shift
          ;;
        --json)
          ps_json=1
          shift
          ;;
        *)
          usage
          ;;
      esac
    done
    if [ "$ps_all" = "1" ]; then
      local_json=$("$local_helper" ps --all --json)
      bridge_json=$(bridge_ps_json --all)
    else
      local_json=$("$local_helper" ps --json)
      bridge_json=$(bridge_ps_json)
    fi
    merged_json=$(merge_arrays "$local_json" "$bridge_json")
    if [ "$ps_json" = "1" ]; then
      printf '%s\n' "$merged_json"
    else
      print_ps_table "$merged_json"
    fi
    ;;
  inspect)
    shift
    [ "$#" -eq 1 ] || usage
    worker_id=$1
    if local_worker_exists "$worker_id"; then
      exec "$local_helper" inspect "$worker_id"
    fi
    bridge_request inspect "$worker_id"
    exit $?
    ;;
  logs)
    shift
    target_worker_id=""
    for arg in "$@"; do
      target_worker_id=$arg
    done
    if [ -z "$target_worker_id" ]; then
      usage
    fi
    if local_worker_exists "$target_worker_id"; then
      exec "$local_helper" logs "$@"
    fi
    bridge_request logs "$@"
    exit $?
    ;;
  debug)
    shift
    debug_json=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json)
          debug_json=1
          shift
          ;;
        *)
          usage
          ;;
      esac
    done

    local_debug_json=$("$local_helper" debug --json)
    if [ -z "$local_debug_json" ]; then
      local_debug_json='{"authority":"guest","state_dir":null,"worker_count":0,"active_worker_count":0,"workers":[],"requests":[]}'
    fi
    if [ -d "$bridge_dir" ]; then
      bridge_debug_json=$(bridge_request debug --json)
      if [ -z "$bridge_debug_json" ]; then
        bridge_debug_json='null'
      fi
    else
      bridge_debug_json='null'
    fi

    if [ "$debug_json" = "1" ]; then
      LOCAL_DEBUG_JSON=$local_debug_json BRIDGE_DEBUG_JSON=$bridge_debug_json python3 - <<'PY'
import json
import os

bridge_payload = os.environ["BRIDGE_DEBUG_JSON"]
result = {
    "local": json.loads(os.environ["LOCAL_DEBUG_JSON"]),
    "bridge": None if bridge_payload == "null" else json.loads(bridge_payload),
}
print(json.dumps(result, indent=2))
PY
      exit 0
    fi

    printf '%s\n' 'Local worker runtime'
    "$local_helper" debug
    if [ -d "$bridge_dir" ]; then
      printf '\n%s\n' 'Host bridge runtime'
      bridge_request debug
    fi
    ;;
  stop)
    shift
    stop_all=0
    stop_json=0
    stop_ids=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --all)
          stop_all=1
          shift
          ;;
        --json)
          stop_json=1
          shift
          ;;
        -*)
          usage
          ;;
        *)
          stop_ids+=("$1")
          shift
          ;;
      esac
    done

    if [ "$stop_all" = "1" ]; then
      [ "${#stop_ids[@]}" -eq 0 ] || usage
      local_json=$("$local_helper" stop --all --json)
      if [ -d "$bridge_dir" ]; then
        bridge_json=$(bridge_request stop --all --json)
      else
        bridge_json='[]'
      fi
      merged_json=$(merge_arrays "$local_json" "$bridge_json")
      if [ "$stop_json" = "1" ]; then
        printf '%s\n' "$merged_json"
      else
        print_worker_ids "$merged_json"
      fi
      exit 0
    fi

    [ "${#stop_ids[@]}" -gt 0 ] || usage
    result_json=$(collect_json_results_for_ids stop -- "${stop_ids[@]}")
    if [ "$stop_json" = "1" ]; then
      if [ "${#stop_ids[@]}" -eq 1 ]; then
        RESULT_JSON=$result_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["RESULT_JSON"])
print(json.dumps(items[0], indent=2))
PY
      else
        printf '%s\n' "$result_json"
      fi
    else
      print_worker_ids "$result_json"
    fi
    ;;
  rm)
    shift
    rm_all=0
    rm_force=0
    rm_json=0
    rm_ids=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --all)
          rm_all=1
          shift
          ;;
        --force)
          rm_force=1
          shift
          ;;
        --json)
          rm_json=1
          shift
          ;;
        -*)
          usage
          ;;
        *)
          rm_ids+=("$1")
          shift
          ;;
      esac
    done

    if [ "$rm_all" = "1" ]; then
      [ "${#rm_ids[@]}" -eq 0 ] || usage
      if [ "$rm_force" = "1" ]; then
        local_json=$("$local_helper" rm --all --force --json)
        if [ -d "$bridge_dir" ]; then
          bridge_json=$(bridge_request rm --all --force --json)
        else
          bridge_json='[]'
        fi
      else
        local_json=$("$local_helper" rm --all --json)
        if [ -d "$bridge_dir" ]; then
          bridge_json=$(bridge_request rm --all --json)
        else
          bridge_json='[]'
        fi
      fi
      merged_json=$(merge_arrays "$local_json" "$bridge_json")
      if [ "$rm_json" = "1" ]; then
        printf '%s\n' "$merged_json"
      else
        print_worker_ids "$merged_json"
      fi
      exit 0
    fi

    [ "${#rm_ids[@]}" -gt 0 ] || usage
    if [ "$rm_force" = "1" ]; then
      result_json=$(collect_json_results_for_ids rm --force -- "${rm_ids[@]}")
    else
      result_json=$(collect_json_results_for_ids rm -- "${rm_ids[@]}")
    fi
    if [ "$rm_json" = "1" ]; then
      if [ "${#rm_ids[@]}" -eq 1 ]; then
        RESULT_JSON=$result_json python3 - <<'PY'
import json
import os

items = json.loads(os.environ["RESULT_JSON"])
print(json.dumps(items[0], indent=2))
PY
      else
        printf '%s\n' "$result_json"
      fi
    else
      print_worker_ids "$result_json"
    fi
    ;;
  prune)
    shift
    prune_force=0
    prune_json=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --force)
          prune_force=1
          shift
          ;;
        --json)
          prune_json=1
          shift
          ;;
        *)
          usage
          ;;
      esac
    done

    if [ "$prune_force" = "1" ]; then
      local_json=$("$local_helper" prune --force --json)
      if [ -d "$bridge_dir" ]; then
        bridge_json=$(bridge_request prune --force --json)
      else
        bridge_json='[]'
      fi
    else
      local_json=$("$local_helper" prune --json)
      if [ -d "$bridge_dir" ]; then
        bridge_json=$(bridge_request prune --json)
      else
        bridge_json='[]'
      fi
    fi
    merged_json=$(merge_arrays "$local_json" "$bridge_json")
    if [ "$prune_json" = "1" ]; then
      printf '%s\n' "$merged_json"
    else
      print_worker_ids "$merged_json"
    fi
    ;;
  ""|help|-h|--help)
    usage 0
    ;;
  *)
    echo "unknown firebreak worker subcommand: $subcommand" >&2
    exit 1
    ;;
esac
