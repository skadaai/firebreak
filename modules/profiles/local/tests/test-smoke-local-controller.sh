#!/usr/bin/env bash
set -eu

controller_lib=@LOCAL_CONTROLLER_LIB@

if ! [ -r "$controller_lib" ]; then
  echo "local controller library is unavailable at $controller_lib" >&2
  exit 1
fi

smoke_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/test-smoke-local-controller.XXXXXX")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  rm -rf "$smoke_tmp_dir"
  exit "$status"
}

trap cleanup EXIT INT TERM

validate_dispatch_lock() {
  shared_runner_workdir=$smoke_tmp_dir/lock-instance
  mkdir -p "$shared_runner_workdir"
  event_log=$smoke_tmp_dir/dispatch-lock.log

  cat >"$smoke_tmp_dir/lock-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
runner_workdir=$1
worker_name=$2
sleep_time=$3
event_log=$4
. @LOCAL_CONTROLLER_LIB@
local_controller_prepare_state
local_controller_acquire_dispatch_lock
printf '%s\n' "$worker_name acquired" >>"$event_log"
sleep "$sleep_time"
printf '%s\n' "$worker_name releasing" >>"$event_log"
local_controller_release_dispatch_lock
EOF
  sed "s|@LOCAL_CONTROLLER_LIB@|$controller_lib|g" "$smoke_tmp_dir/lock-helper.sh" >"$smoke_tmp_dir/lock-helper.sh.tmp"
  mv "$smoke_tmp_dir/lock-helper.sh.tmp" "$smoke_tmp_dir/lock-helper.sh"
  chmod 0555 "$smoke_tmp_dir/lock-helper.sh"

  "$smoke_tmp_dir/lock-helper.sh" "$shared_runner_workdir" first 2 "$event_log" &
  first_pid=$!
  sleep 0.2
  "$smoke_tmp_dir/lock-helper.sh" "$shared_runner_workdir" second 0 "$event_log"
  wait "$first_pid"

  expected_log=$smoke_tmp_dir/dispatch-lock.expected
  cat >"$expected_log" <<'EOF'
first acquired
first releasing
second acquired
second releasing
EOF

  if ! cmp -s "$event_log" "$expected_log"; then
    cat "$event_log" >&2
    echo "local controller dispatch lock did not serialize requests" >&2
    exit 1
  fi
}

validate_stale_build_invalidation() {
  runner_workdir=$smoke_tmp_dir/build-instance
  export runtime_generation=current-build
  mkdir -p "$runner_workdir"
  # shellcheck disable=SC1090
  . "$controller_lib"
  local_controller_prepare_state
  state_dir=${local_controller_state_dir:-}
  pid_file=${local_controller_pid_file:-}
  build_id_file=${local_controller_build_id_file:-}
  runtime_dir_file=${local_controller_runtime_dir_file:-}

  mkdir -p "$state_dir"

  sleep 30 &
  stale_pid=$!
  printf '%s\n' "$stale_pid" >"$pid_file"
  printf '%s\n' old-build >"$build_id_file"

  if local_controller_matches_build_id; then
    echo "local controller matched a stale build id" >&2
    exit 1
  fi

  local_controller_stop_running

  if kill -0 "$stale_pid" 2>/dev/null; then
    kill -9 "$stale_pid" 2>/dev/null || true
    wait "$stale_pid" 2>/dev/null || true
    echo "local controller failed to stop a stale daemon pid" >&2
    exit 1
  fi

  for stale_path in \
    "$pid_file" \
    "$runtime_dir_file" \
    "$build_id_file"; do
    if [ -e "$stale_path" ]; then
      echo "local controller left stale state behind: $stale_path" >&2
      exit 1
    fi
  done
}

validate_dispatch_lock
validate_stale_build_invalidation
printf '%s\n' "PASS: test-smoke-local-controller"
