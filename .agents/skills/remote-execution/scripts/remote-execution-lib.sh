#!/usr/bin/env bash

set -euo pipefail

remote_execution_init() {
  NSC_MACHINE=${NSC_MACHINE:-"4x8"}
  NSC_DURATION=${NSC_DURATION:-"30m"}
  NSC_NIX_CACHE_TAG=${NSC_NIX_CACHE_TAG:-"nix-store"}
  NSC_DEBUG=${NSC_DEBUG:-"0"}
  NSC_LOG_DIR=${NSC_LOG_DIR:-""}
  NSC_HEARTBEAT_SECONDS=${NSC_HEARTBEAT_SECONDS:-"30"}

  if [[ -n "$NSC_LOG_DIR" ]]; then
    RUN_DIR=$NSC_LOG_DIR
    mkdir -p "$RUN_DIR"
  else
    RUN_DIR=$(mktemp -d -t remote-execution.XXXXXX)
  fi

  INFRA_LOG="$RUN_DIR/infra.log"
  EXECUTION_LOG="$RUN_DIR/execution.txt"
  SUMMARY_FILE="$RUN_DIR/summary.txt"
  INSTANCE_ID_FILE="$RUN_DIR/instance-id"
  ARCHIVE_FILE="$RUN_DIR/workspace.tar.gz"
  REMOTE_ARCHIVE_PATH="/tmp/remote-execution-workspace.tar.gz"
  REMOTE_EXECUTION_SCRIPT_FILE="$RUN_DIR/remote-execution.sh"

  : >"$INFRA_LOG"
  : >"$EXECUTION_LOG"
  : >"$SUMMARY_FILE"

  INSTANCE_ID=""
  REMOTE_EXECUTION_PHASE="init"
}

remote_execution_note() {
  printf '%s\n' "$*"
}

remote_execution_debug_enabled() {
  [[ "$NSC_DEBUG" != "0" ]]
}

remote_execution_filter_nsc_noise() {
  sed '/^warning: Failed to write token cache: open \/var\/run\/nsc\/token\.cache: permission denied$/d'
}

remote_execution_record_command() {
  local phase=$1
  shift

  printf '\n[%s] $' "$phase" >>"$INFRA_LOG"
  printf ' %q' "$@" >>"$INFRA_LOG"
  printf '\n' >>"$INFRA_LOG"
}

remote_execution_run_infra() {
  local phase=$1
  shift

  remote_execution_record_command "$phase" "$@"

  if remote_execution_debug_enabled; then
    "$@" 2>&1 | remote_execution_filter_nsc_noise | tee -a "$INFRA_LOG"
    return "${PIPESTATUS[0]}"
  fi

  "$@" 2>&1 | remote_execution_filter_nsc_noise >>"$INFRA_LOG"
  return "${PIPESTATUS[0]}"
}

remote_execution_run_remote_infra() {
  local phase=$1
  local script=$2

  printf '\n[%s] remote script\n%s\n' "$phase" "$script" >>"$INFRA_LOG"

  if remote_execution_debug_enabled; then
    { printf '%s\n' "$script"; } | nsc ssh --disable-pty "$INSTANCE_ID" -- bash -s -- 2>&1 | remote_execution_filter_nsc_noise | tee -a "$INFRA_LOG"
    return "${PIPESTATUS[1]}"
  fi

  { printf '%s\n' "$script"; } | nsc ssh --disable-pty "$INSTANCE_ID" -- bash -s -- 2>&1 | remote_execution_filter_nsc_noise >>"$INFRA_LOG"
  return "${PIPESTATUS[1]}"
}

remote_execution_run_remote_stream() {
  local phase=$1
  local script=$2
  local output_pid
  local heartbeat_pid
  local status

  REMOTE_EXECUTION_PHASE=$phase
  printf '%s\n' "$script" >"$REMOTE_EXECUTION_SCRIPT_FILE"
  printf '\n[%s] execution script saved to %s\n' "$phase" "$REMOTE_EXECUTION_SCRIPT_FILE" >>"$INFRA_LOG"

  : >"$EXECUTION_LOG"

  (
    { printf '%s\n' "$script"; } | nsc ssh --disable-pty "$INSTANCE_ID" -- bash -s -- 2>&1 | remote_execution_filter_nsc_noise | tee -a "$EXECUTION_LOG"
    exit "${PIPESTATUS[1]}"
  ) &
  output_pid=$!

  (
    local last_size=0
    local current_size=0
    local quiet_for=0

    while kill -0 "$output_pid" 2>/dev/null; do
      sleep "$NSC_HEARTBEAT_SECONDS"

      if ! kill -0 "$output_pid" 2>/dev/null; then
        break
      fi

      current_size=$(wc -c <"$EXECUTION_LOG" 2>/dev/null || echo 0)

      if [[ "$current_size" -eq "$last_size" ]]; then
        quiet_for=$((quiet_for + NSC_HEARTBEAT_SECONDS))
        printf '[execution] still running (%ss without output)\n' "$quiet_for"
        printf '[execution-heartbeat] still running (%ss without output)\n' "$quiet_for" >>"$INFRA_LOG"
      else
        last_size=$current_size
        quiet_for=0
      fi
    done
  ) &
  heartbeat_pid=$!

  wait "$output_pid"
  status=$?
  kill "$heartbeat_pid" 2>/dev/null || true
  wait "$heartbeat_pid" 2>/dev/null || true
  return "$status"
}

remote_execution_require_prereqs() {
  if ! command -v nsc >/dev/null 2>&1; then
    echo "nsc is required but not on PATH" >&2
    echo "install the Namespace CLI in the agent environment (Nix package: namespace-cli)" >&2
    exit 127
  fi

  if ! nsc auth check-login >/dev/null 2>&1; then
    echo "nsc is installed but not authenticated. Run 'nsc auth login' first." >&2
    exit 1
  fi
}

remote_execution_require_archive_tools() {
  if ! command -v tar >/dev/null 2>&1; then
    echo "tar is required locally. Provide GNU tar (package name: gnutar) and retry." >&2
    exit 127
  fi

  if ! command -v gzip >/dev/null 2>&1; then
    echo "gzip is required locally. Provide gzip and retry." >&2
    exit 127
  fi
}

remote_execution_require_modern_cli() {
  if ! nsc instance upload --help >/dev/null 2>&1; then
    echo "the installed nsc does not support 'nsc instance upload'" >&2
    echo "install a newer Namespace CLI before using this skill" >&2
    exit 1
  fi
}

remote_execution_write_summary() {
  local status=$1
  local phase=$2
  local exit_code=$3

  cat >"$SUMMARY_FILE" <<EOF
status=$status
phase=$phase
exit_code=$exit_code
run_dir=$RUN_DIR
instance_id=${INSTANCE_ID:-}
infra_log=$INFRA_LOG
execution_log=$EXECUTION_LOG
execution_script=$REMOTE_EXECUTION_SCRIPT_FILE
EOF
}

remote_execution_fail() {
  local phase=$1
  local exit_code=${2:-1}

  REMOTE_EXECUTION_PHASE=$phase
  remote_execution_write_summary "failed" "$phase" "$exit_code"

  printf 'Remote execution failed during phase: %s\n' "$phase" >&2
  printf 'Run directory: %s\n' "$RUN_DIR" >&2
  printf 'Summary: %s\n' "$SUMMARY_FILE" >&2
  printf 'Infra log: %s\n' "$INFRA_LOG" >&2

  if [[ -s "$EXECUTION_LOG" ]]; then
    printf 'Execution log: %s\n' "$EXECUTION_LOG" >&2
    printf '\nExecution output tail:\n' >&2
    tail -n 80 "$EXECUTION_LOG" >&2
  fi

  if [[ -s "$INFRA_LOG" ]]; then
    printf '\nInfra log tail:\n' >&2
    tail -n 40 "$INFRA_LOG" >&2
  fi

  exit "$exit_code"
}

remote_execution_success() {
  remote_execution_write_summary "ok" "${REMOTE_EXECUTION_PHASE:-execution}" 0

  printf 'Execution succeeded.\n'
  printf 'Run directory: %s\n' "$RUN_DIR"
  printf 'Summary: %s\n' "$SUMMARY_FILE"
  printf 'Execution log: %s\n' "$EXECUTION_LOG"
  printf 'Infra log: %s\n' "$INFRA_LOG"
}

remote_execution_cleanup() {
  local status=$?

  if [[ -n "${INSTANCE_ID:-}" ]]; then
    remote_execution_note "→ Destroying instance $INSTANCE_ID..."
    remote_execution_run_infra "teardown" nsc destroy --force "$INSTANCE_ID" || true
    INSTANCE_ID=""
  fi

  rm -f "$INSTANCE_ID_FILE" "$ARCHIVE_FILE"

  return "$status"
}

remote_execution_wait_for_shell() {
  local attempt output

  for attempt in $(seq 1 40); do
    if output=$(nsc ssh --disable-pty "$INSTANCE_ID" -- true 2>&1 | remote_execution_filter_nsc_noise); then
      printf '\n[ssh-ready] attempt=%s\n%s\n' "$attempt" "$output" >>"$INFRA_LOG"
      return 0
    fi

    printf '\n[ssh-ready] attempt=%s\n%s\n' "$attempt" "$output" >>"$INFRA_LOG"

    if printf '%s\n' "$output" | grep -qiE 'FailedPrecondition|failed to start'; then
      printf '%s\n' "$output" >&2
      return 1
    fi

    sleep 3
  done

  echo "Timed out waiting for instance $INSTANCE_ID to accept nsc ssh." >&2
  return 124
}

remote_execution_create_instance() {
  REMOTE_EXECUTION_PHASE="instance-create"
  remote_execution_note "→ Creating ephemeral instance (shape: $NSC_MACHINE, duration: $NSC_DURATION)..."

  if remote_execution_run_infra \
    "instance-create" \
    nsc create \
      --bare \
      --machine_type "$NSC_MACHINE" \
      --duration "$NSC_DURATION" \
      --volume "cache:$NSC_NIX_CACHE_TAG:/nix:50gb" \
      --purpose "Remote execution" \
      --cidfile "$INSTANCE_ID_FILE"; then
    :
  else
    local status=$?
    remote_execution_fail "instance-create" "$status"
  fi

  INSTANCE_ID=$(cat "$INSTANCE_ID_FILE")
  remote_execution_note "→ Instance: $INSTANCE_ID"
}

remote_execution_wait_until_ready() {
  REMOTE_EXECUTION_PHASE="ssh-ready"
  remote_execution_note "→ Waiting for remote shell..."

  if remote_execution_wait_for_shell; then
    :
  else
    local status=$?
    remote_execution_fail "ssh-ready" "$status"
  fi
}

remote_execution_ensure_nix() {
  REMOTE_EXECUTION_PHASE="nix-bootstrap"
  remote_execution_note "→ Ensuring Nix is installed..."

  if remote_execution_run_remote_infra "nix-bootstrap" "
set -euo pipefail
NIX_BIN=/nix/var/nix/profiles/default/bin/nix
if [[ -x \$NIX_BIN ]]; then
  echo \"Nix found in cache, skipping install.\"
else
  echo \"Installing Nix (first run - will be cached for future runs)...\"
  curl -fsSL https://install.determinate.systems/nix \
    | sh -s -- install linux --determinate --init none --no-confirm
fi
"; then
    :
  else
    local status=$?
    remote_execution_fail "nix-bootstrap" "$status"
  fi
}

remote_execution_pack_workspace() {
  REMOTE_EXECUTION_PHASE="archive"
  remote_execution_note "→ Creating workspace archive..."

  if remote_execution_run_infra \
    "archive" \
    tar -czf "$ARCHIVE_FILE" \
      --exclude=.git \
      --exclude=result \
      --exclude=.direnv \
      --exclude=.agent-sandbox-codex-ssh \
      .; then
    :
  else
    local status=$?
    remote_execution_fail "archive" "$status"
  fi
}

remote_execution_upload_workspace() {
  REMOTE_EXECUTION_PHASE="upload"
  remote_execution_note "→ Uploading workspace..."

  if remote_execution_run_infra \
    "upload" \
    nsc instance upload "$INSTANCE_ID" "$ARCHIVE_FILE" "$REMOTE_ARCHIVE_PATH"; then
    :
  else
    local status=$?
    remote_execution_fail "upload" "$status"
  fi

  if remote_execution_run_remote_infra "upload-unpack" "
set -euo pipefail
rm -rf /workspace
mkdir -p /workspace
tar -xzf \"$REMOTE_ARCHIVE_PATH\" -C /workspace
rm -f \"$REMOTE_ARCHIVE_PATH\"
"; then
    :
  else
    local status=$?
    remote_execution_fail "upload-unpack" "$status"
  fi
}

remote_execution_run_workspace_script() {
  local script=$1

  REMOTE_EXECUTION_PHASE="execution"
  remote_execution_note "→ Running remote execution..."

  if remote_execution_run_remote_stream "execution" "$script"; then
    :
  else
    local status=$?
    remote_execution_fail "execution" "$status"
  fi
}
