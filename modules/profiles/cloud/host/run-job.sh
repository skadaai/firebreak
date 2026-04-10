set -eu

job_id=""
workspace_dir=""
output_dir=""
config_dir=""
prompt=""
prompt_file=""
timeout_seconds=${FIREBREAK_JOB_TIMEOUT_SECONDS:-300}
max_jobs=${FIREBREAK_MAX_JOBS:-1}
state_dir=${FIREBREAK_STATE_DIR:-@DEFAULT_STATE_DIR@}
firebreak_tmp_root=${FIREBREAK_TMPDIR:-${XDG_CACHE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.cache}/firebreak/tmp}

usage() {
  cat <<'EOF' >&2
usage: firebreak-cloud-job \
  --job-id ID \
  --workspace-dir PATH \
  --output-dir PATH \
  [--config-dir PATH] \
  [--prompt TEXT | --prompt-file FILE] \
  [--timeout-seconds N] \
  [--max-jobs N] \
  [--state-dir PATH]
EOF
  exit 1
}

reject_whitespace_path() {
  path=$1
  description=$2
  case "$path" in
    *[[:space:]]*)
      echo "$description contains whitespace, which microvm runtime share injection does not support: $path" >&2
      exit 1
      ;;
  esac
}

validate_job_id() {
  case "$1" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "job id must be a single path-safe token without whitespace: $1" >&2
      exit 1
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --job-id)
      job_id=$2
      shift 2
      ;;
    --workspace-dir)
      workspace_dir=$2
      shift 2
      ;;
    --output-dir)
      output_dir=$2
      shift 2
      ;;
    --config-dir)
      config_dir=$2
      shift 2
      ;;
    --prompt)
      prompt=$2
      shift 2
      ;;
    --prompt-file)
      prompt_file=$2
      shift 2
      ;;
    --timeout-seconds)
      timeout_seconds=$2
      shift 2
      ;;
    --max-jobs)
      max_jobs=$2
      shift 2
      ;;
    --state-dir)
      state_dir=$2
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$job_id" ] || [ -z "$workspace_dir" ] || [ -z "$output_dir" ]; then
  usage
fi

validate_job_id "$job_id"

case "$workspace_dir" in
  /*) ;;
  *) echo "--workspace-dir must be absolute: $workspace_dir" >&2; exit 1 ;;
esac
case "$output_dir" in
  /*) ;;
  *) echo "--output-dir must be absolute: $output_dir" >&2; exit 1 ;;
esac
case "$state_dir" in
  /*) ;;
  *) echo "--state-dir must be absolute: $state_dir" >&2; exit 1 ;;
esac

if [ -n "$config_dir" ]; then
  case "$config_dir" in
    /*) ;;
    *) echo "--config-dir must be absolute: $config_dir" >&2; exit 1 ;;
  esac
fi

if [ -n "$prompt" ] && [ -n "$prompt_file" ]; then
  echo "use either --prompt or --prompt-file, not both" >&2
  exit 1
fi

if [ -z "$prompt" ] && [ -z "$prompt_file" ]; then
  echo "either --prompt or --prompt-file is required" >&2
  exit 1
fi

if [ -z "$config_dir" ]; then
  config_dir=$output_dir/config
fi

reject_whitespace_path "$workspace_dir" "workspace directory"
reject_whitespace_path "$output_dir" "output directory"
reject_whitespace_path "$config_dir" "config directory"
reject_whitespace_path "$state_dir" "state directory"
if [ -n "$prompt_file" ]; then
  reject_whitespace_path "$prompt_file" "prompt file"
fi

mkdir -p "$output_dir" "$config_dir" "$state_dir"
mkdir -p "$firebreak_tmp_root"

job_state_dir=$state_dir/jobs/$job_id
running_dir=$state_dir/running
capacity_lock=$state_dir/capacity.lock
mkdir -p "$job_state_dir" "$running_dir"

stderr_path=$output_dir/stderr
stdout_path=$output_dir/stdout
exit_code_path=$output_dir/exit_code
runner_stderr_log=$job_state_dir/runner.stderr
virtiofsd_workspace_log=$job_state_dir/virtiofsd-workspace.log
virtiofsd_config_log=$job_state_dir/virtiofsd-config.log
virtiofsd_output_log=$job_state_dir/virtiofsd-output.log

persist_failure() {
  message=$1
  code=$2
  printf '%s\n' "$message" >>"$stderr_path"
  printf '%s\n' "$code" >"$exit_code_path"
}

if ! [ -w "$output_dir" ]; then
  echo "output directory is not writable: $output_dir" >&2
  exit 1
fi

if ! [ -w "$config_dir" ]; then
  echo "config directory is not writable: $config_dir" >&2
  exit 1
fi

rm -f "$stdout_path" "$stderr_path" "$exit_code_path"

if ! [ -d "$workspace_dir" ]; then
  persist_failure "workspace directory is missing: $workspace_dir" 2
  exit 2
fi

if [ -n "$prompt_file" ] && ! [ -r "$prompt_file" ]; then
  persist_failure "prompt file is missing: $prompt_file" 2
  exit 2
fi

exec 9>"$capacity_lock"
flock -x 9
current_jobs=$(find "$running_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
if [ "$current_jobs" -ge "$max_jobs" ]; then
  flock -u 9
  echo "host capacity exhausted: $current_jobs running jobs, max $max_jobs" >&2
  persist_failure "host capacity exhausted: $current_jobs running jobs, max $max_jobs" 125
  exit 125
fi

job_lock_dir=$running_dir/$job_id
if ! mkdir "$job_lock_dir" 2>/dev/null; then
  flock -u 9
  echo "job id is already active: $job_id" >&2
  persist_failure "job id is already active: $job_id" 126
  exit 126
fi
flock -u 9

runtime_dir=$(mktemp -d "$firebreak_tmp_root/cloud-job-runtime.XXXXXX")
input_dir=$runtime_dir/input
runner_workdir=$runtime_dir/vm
workspace_socket=$runtime_dir/workspace.sock
config_socket=$runtime_dir/config.sock
output_socket=$runtime_dir/output.sock
mkdir -p "$input_dir" "$runner_workdir"

# shellcheck disable=SC2329
cleanup() {
  if [ -n "${workspace_virtiofsd_pid:-}" ]; then
    kill "$workspace_virtiofsd_pid" 2>/dev/null || true
    wait "$workspace_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${config_virtiofsd_pid:-}" ]; then
    kill "$config_virtiofsd_pid" 2>/dev/null || true
    wait "$config_virtiofsd_pid" 2>/dev/null || true
  fi
  if [ -n "${output_virtiofsd_pid:-}" ]; then
    kill "$output_virtiofsd_pid" 2>/dev/null || true
    wait "$output_virtiofsd_pid" 2>/dev/null || true
  fi
  rm -rf "$runtime_dir"
  rmdir "$job_lock_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ -n "$prompt" ]; then
  printf '%s\n' "$prompt" > "$input_dir/prompt"
else
  cp "$prompt_file" "$input_dir/prompt"
fi
printf '%s\n' "$(id -u)" > "$input_dir/host-uid"
printf '%s\n' "$(id -g)" > "$input_dir/host-gid"

start_virtiofsd() {
  shared_dir=$1
  socket_path=$2
  log_path=$3
  virtiofsd \
    --socket-path="$socket_path" \
    --shared-dir="$shared_dir" \
    --sandbox=none \
    --posix-acl \
    --xattr >"$log_path" 2>&1 &
  started_virtiofsd_pid=$!

  for _ in $(seq 1 50); do
    if [ -S "$socket_path" ]; then
      return 0
    fi
    sleep 0.1
  done

  kill "$started_virtiofsd_pid" 2>/dev/null || true
  wait "$started_virtiofsd_pid" 2>/dev/null || true
  echo "virtiofsd did not create socket: $socket_path" >&2
  exit 1
}

start_virtiofsd "$workspace_dir" "$workspace_socket" "$virtiofsd_workspace_log"
workspace_virtiofsd_pid=$started_virtiofsd_pid
start_virtiofsd "$config_dir" "$config_socket" "$virtiofsd_config_log"
config_virtiofsd_pid=$started_virtiofsd_pid
start_virtiofsd "$output_dir" "$output_socket" "$virtiofsd_output_log"
output_virtiofsd_pid=$started_virtiofsd_pid

runner_status=0
runner_pid=""
timed_out=0

set +e
# shellcheck disable=SC2016
setsid env \
  MICROVM_WORKSPACE_SOCKET="$workspace_socket" \
  MICROVM_TOOL_JOB_INPUT_DIR="$input_dir" \
  MICROVM_SHARED_STATE_ROOT_SOCKET="$config_socket" \
  MICROVM_COMMAND_OUTPUT_SOCKET="$output_socket" \
  sh -c 'cd "$1" && exec "$2"' sh "$runner_workdir" @RUNNER@ >"$job_state_dir/runner.stdout" 2>"$runner_stderr_log" &
runner_pid=$!
set -e

deadline=$(( $(date +%s) + timeout_seconds ))
while kill -0 "$runner_pid" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    timed_out=1
    break
  fi
  sleep 1
done

if [ "$timed_out" -eq 1 ]; then
  kill -TERM -- "-$runner_pid" 2>/dev/null || true
  for _ in $(seq 1 50); do
    if ! kill -0 "$runner_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$runner_pid" 2>/dev/null; then
    kill -KILL -- "-$runner_pid" 2>/dev/null || true
  fi
  wait "$runner_pid" 2>/dev/null || true
  persist_failure "job exceeded runtime limit of ${timeout_seconds}s" 124
  exit 124
fi

set +e
wait "$runner_pid"
runner_status=$?
set -e

if [ -f "$stdout_path" ]; then
  cat "$stdout_path"
fi
if [ -f "$stderr_path" ]; then
  cat "$stderr_path" >&2
fi

if [ -f "$exit_code_path" ]; then
  IFS= read -r command_status < "$exit_code_path" || command_status=$runner_status
  if [ "$command_status" -ne 0 ] && [ -s "$runner_stderr_log" ]; then
    cat "$runner_stderr_log" >&2
  fi
  exit "$command_status"
fi

if [ -s "$runner_stderr_log" ]; then
  cat "$runner_stderr_log" >&2
fi
if [ -s "$virtiofsd_workspace_log" ]; then
  cat "$virtiofsd_workspace_log" >&2
fi
if [ -s "$virtiofsd_config_log" ]; then
  cat "$virtiofsd_config_log" >&2
fi
if [ -s "$virtiofsd_output_log" ]; then
  cat "$virtiofsd_output_log" >&2
fi

persist_failure "job failed before guest outputs were captured" "$runner_status"
exit "$runner_status"
