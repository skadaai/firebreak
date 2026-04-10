firebreak_reset_command_response_dir() {
  command_response_dir=$1

  rm -f \
    "$command_response_dir/request.json" \
    "$command_response_dir/attach_stage" \
    "$command_response_dir/exit_code" \
    "$command_response_dir/stdout" \
    "$command_response_dir/stderr" \
    "$command_response_dir/profile-guest.tsv" \
    "$command_response_dir/command-signals.stream" \
    "$command_response_dir/command-processes.txt" \
    "$command_response_dir/command-tty.txt"
}

firebreak_write_command_request() {
  command_response_dir=$1
  command_request_mode=$2
  command_request_value=$3
  command_request_start_dir=$4
  command_request_term=$5
  command_request_columns=$6
  command_request_lines=$7
  command_request_capture_systemd_profile=$8
  command_request_id=$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID:-$$}-$(python3 -c 'import secrets; print(secrets.token_hex(4))')
  command_request_path=$command_response_dir/request.json

  firebreak_reset_command_response_dir "$command_response_dir"

  REQUEST_PATH=$command_request_path \
  REQUEST_ID=$command_request_id \
  REQUEST_SESSION_MODE=$command_request_mode \
  REQUEST_COMMAND=$command_request_value \
  REQUEST_START_DIR=$command_request_start_dir \
  REQUEST_TERM=$command_request_term \
  REQUEST_COLUMNS=$command_request_columns \
  REQUEST_LINES=$command_request_lines \
  REQUEST_CAPTURE_SYSTEMD_PROFILE=$command_request_capture_systemd_profile \
  python3 - <<'PY'
import json
import os
import tempfile

payload = {
    "request_id": os.environ["REQUEST_ID"],
    "session_mode": os.environ["REQUEST_SESSION_MODE"],
    "command": os.environ["REQUEST_COMMAND"],
    "start_dir": os.environ["REQUEST_START_DIR"],
    "term": os.environ["REQUEST_TERM"],
    "columns": os.environ["REQUEST_COLUMNS"],
    "lines": os.environ["REQUEST_LINES"],
    "capture_systemd_profile": os.environ["REQUEST_CAPTURE_SYSTEMD_PROFILE"],
}

request_path = os.environ["REQUEST_PATH"]
request_dir = os.path.dirname(request_path)
with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=request_dir, delete=False) as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
    temp_path = handle.name
os.replace(temp_path, request_path)
PY
}
