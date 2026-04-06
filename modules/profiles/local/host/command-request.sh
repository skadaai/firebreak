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
  command_request_id=$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID:-$$}
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
  python3 - <<'PY'
import json
import os

payload = {
    "request_id": os.environ["REQUEST_ID"],
    "session_mode": os.environ["REQUEST_SESSION_MODE"],
    "command": os.environ["REQUEST_COMMAND"],
    "start_dir": os.environ["REQUEST_START_DIR"],
    "term": os.environ["REQUEST_TERM"],
    "columns": os.environ["REQUEST_COLUMNS"],
    "lines": os.environ["REQUEST_LINES"],
}

with open(os.environ["REQUEST_PATH"], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}
