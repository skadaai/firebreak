command_request_dir=@COMMAND_OUTPUT_MOUNT@
command_request_file=$command_request_dir/request.json
export command_request_loaded=0
export command_request_id=""
export command_request_session_mode=""
export command_request_command=""
export command_request_start_dir=""
export command_request_term=""
export command_request_columns=""
export command_request_lines=""
export command_request_capture_systemd_profile="0"

load_command_request() {
  if ! [ -r "$command_request_file" ]; then
    echo "command request is unavailable at $command_request_file" >&2
    return 1
  fi

  COMMAND_REQUEST_FILE="$command_request_file" @PYTHON3@ - <<'PY'
import json
import os
import shlex
import sys

path = os.environ["COMMAND_REQUEST_FILE"]
try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, ValueError) as exc:
    print(f"invalid command request at {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)

def as_text(name: str) -> str:
    value = payload.get(name, "")
    if value is None:
        return ""
    return str(value)

session_mode = as_text("session_mode")
if session_mode not in {"command-exec", "command-attach-exec"}:
    print(
        f"invalid command request session_mode in {path}: {session_mode or '<empty>'}",
        file=sys.stderr,
    )
    raise SystemExit(1)

columns = as_text("columns")
if columns and not columns.isdigit():
    print(f"invalid command request columns in {path}: {columns}", file=sys.stderr)
    raise SystemExit(1)

lines = as_text("lines")
if lines and not lines.isdigit():
    print(f"invalid command request lines in {path}: {lines}", file=sys.stderr)
    raise SystemExit(1)

assignments = {
    "command_request_loaded": "1",
    "command_request_id": as_text("request_id"),
    "command_request_session_mode": session_mode,
    "command_request_command": as_text("command"),
    "command_request_start_dir": as_text("start_dir"),
    "command_request_term": as_text("term"),
    "command_request_columns": columns,
    "command_request_lines": lines,
    "command_request_capture_systemd_profile": "1" if as_text("capture_systemd_profile") == "1" else "0",
}

for key, value in assignments.items():
    print(f"{key}={shlex.quote(value)}")
PY
}

ensure_command_request_loaded() {
  if [ "${command_request_loaded:-0}" = "1" ]; then
    return 0
  fi

  command_request_assignments=$(load_command_request) || return 1
  eval "$command_request_assignments"
  export \
    command_request_loaded \
    command_request_id \
    command_request_session_mode \
    command_request_command \
    command_request_start_dir \
    command_request_term \
    command_request_columns \
    command_request_lines \
    command_request_capture_systemd_profile
  export FIREBREAK_COMMAND_REQUEST_ID=${command_request_id:-}
}
