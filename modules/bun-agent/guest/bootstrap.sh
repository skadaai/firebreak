#!/usr/bin/env bash
set -eu

export DEV_HOME=@DEV_HOME@
tool_home=$DEV_HOME
if [ -d @AGENT_TOOLS_MOUNT@ ]; then
  tool_home=@AGENT_TOOLS_MOUNT@
fi
export HOME="$DEV_HOME"
export BUN_INSTALL="$tool_home/.bun"
export LOCAL_BIN="$tool_home/.local/bin"
export XDG_CONFIG_HOME="$tool_home/.config"
export XDG_CACHE_HOME="$tool_home/.cache"
export XDG_STATE_HOME="$tool_home/.local/state"
export TMPDIR="$XDG_CACHE_HOME/tmp"
export BUN_TMPDIR="$TMPDIR"
export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install/cache"
export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/transpiler"
export PATH="$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
export AGENT_SPEC_MARKER_DIR="$XDG_STATE_HOME/firebreak-bun-agent"
export AGENT_SPEC_MARKER_PATH="$AGENT_SPEC_MARKER_DIR/@AGENT_BIN@.spec"
export AGENT_GLOBAL_BIN="$BUN_INSTALL/bin/@AGENT_BIN@"
export FIREBREAK_GUEST_STATE_DIR=/run/firebreak-worker
export FIREBREAK_BOOTSTRAP_STATE_PATH="$FIREBREAK_GUEST_STATE_DIR/bootstrap-state.json"
export FIREBREAK_SHARED_BOOTSTRAP_STATE_PATH="@AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json"
export FIREBREAK_BOOTSTRAP_READY_MARKER="@BOOTSTRAP_READY_MARKER@"
export FIREBREAK_BOOTSTRAP_LOCK_PATH="$tool_home/.firebreak-bootstrap.lock"
shared_tool_home=0
if [ "$tool_home" != "$DEV_HOME" ]; then
  shared_tool_home=1
fi
agent_wrapper_path="$LOCAL_BIN/@AGENT_BIN@"
bootstrap_lock_acquired=0

log_phase() {
  printf '[firebreak-bootstrap] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_bootstrap_state() {
  bootstrap_phase=$1
  bootstrap_status=$2
  bootstrap_detail=$3
  updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat >"$FIREBREAK_BOOTSTRAP_STATE_PATH" <<EOF
{
  "source": "guest-bootstrap",
  "phase": "$(json_escape "$bootstrap_phase")",
  "status": "$(json_escape "$bootstrap_status")",
  "detail": "$(json_escape "$bootstrap_detail")",
  "agent_bin": "@AGENT_BIN@",
  "package_spec": "$(json_escape "@AGENT_PACKAGE_SPEC@")",
  "updated_at": "$updated_at"
}
EOF
  if [ -d "@AGENT_EXEC_OUTPUT_MOUNT@" ]; then
    if ! cp "$FIREBREAK_BOOTSTRAP_STATE_PATH" "$FIREBREAK_SHARED_BOOTSTRAP_STATE_PATH" 2>/dev/null; then
      log_phase "bootstrap-state-sync-skip $FIREBREAK_SHARED_BOOTSTRAP_STATE_PATH"
    fi
  fi
}

maybe_chown_dev() {
  target_path=$1
  if [ "$(id -u)" -ne 0 ]; then
    return 0
  fi
  if [ "$shared_tool_home" = "1" ]; then
    log_phase "ownership-skip $target_path"
    return 0
  fi
  if chown @DEV_USER@:@DEV_USER@ "$target_path" 2>/dev/null; then
    return 0
  fi
  echo "failed to chown bootstrap-managed path: $target_path" >&2
  return 1
}

ensure_bootstrap_dir() {
  target_path=$1
  mkdir -p "$target_path"
  chmod 0755 "$target_path" 2>/dev/null || true
}

acquire_bootstrap_lock() {
  exec 9>"$FIREBREAK_BOOTSTRAP_LOCK_PATH"
  flock 9
  bootstrap_lock_acquired=1
}

release_bootstrap_lock() {
  if [ "$bootstrap_lock_acquired" != "1" ]; then
    return 0
  fi
  flock -u 9 2>/dev/null || true
  exec 9>&-
  bootstrap_lock_acquired=0
}

current_bootstrap_phase=init
bootstrap_trap() {
  exit_code=$?
  release_bootstrap_lock
  if [ "$exit_code" -ne 0 ]; then
    rm -f "$FIREBREAK_BOOTSTRAP_READY_MARKER"
    write_bootstrap_state "$current_bootstrap_phase" "error" "bootstrap-exit:$exit_code"
  fi
  exit "$exit_code"
}
trap bootstrap_trap EXIT

log_phase "toolchain-prepare-start @AGENT_DISPLAY_NAME@"
log_phase "tool-home $tool_home"
log_phase "tool-ready-marker $FIREBREAK_BOOTSTRAP_READY_MARKER"
ensure_bootstrap_dir "$tool_home"
ensure_bootstrap_dir "$FIREBREAK_GUEST_STATE_DIR"
ensure_bootstrap_dir "$(dirname "$FIREBREAK_BOOTSTRAP_READY_MARKER")"
current_bootstrap_phase=toolchain-prepare-start
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_DISPLAY_NAME@"
acquire_bootstrap_lock

installed_spec=""
if [ -r "$AGENT_SPEC_MARKER_PATH" ]; then
  installed_spec=$(cat "$AGENT_SPEC_MARKER_PATH")
fi

if [ -x "$AGENT_GLOBAL_BIN" ] \
  && [ -x "$agent_wrapper_path" ] \
  && [ "$installed_spec" = "@AGENT_PACKAGE_SPEC@" ] \
  && [ -r "$FIREBREAK_BOOTSTRAP_READY_MARKER" ]; then
  log_phase "toolchain-cache-hit @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-cache-hit
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
  log_phase "wrapper-ready @AGENT_BIN@"
  current_bootstrap_phase=wrapper-ready
  write_bootstrap_state "$current_bootstrap_phase" "ready" "@AGENT_BIN@"
  exit 0
fi

rm -f "$FIREBREAK_BOOTSTRAP_READY_MARKER"

for bootstrap_dir in \
  "$BUN_INSTALL/bin" \
  "$LOCAL_BIN" \
  "$TMPDIR" \
  "$BUN_INSTALL_CACHE_DIR" \
  "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" \
  "$XDG_CONFIG_HOME" \
  "$AGENT_SPEC_MARKER_DIR"; do
  ensure_bootstrap_dir "$bootstrap_dir"
done
log_phase "toolchain-directories-ready @AGENT_DISPLAY_NAME@"
current_bootstrap_phase=toolchain-directories-ready
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_DISPLAY_NAME@"
log_phase "toolchain-ownership-ready @AGENT_DISPLAY_NAME@"
current_bootstrap_phase=toolchain-ownership-ready
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_DISPLAY_NAME@"

cat > "$LOCAL_BIN/@AGENT_BIN@" <<'EOF'
#!/bin/sh
set -eu
agent_bin="$BUN_INSTALL/bin/@AGENT_BIN@"
if [ ! -x "$agent_bin" ]; then
  echo "@AGENT_DISPLAY_NAME@ is not installed in $agent_bin" >&2
  echo "Restart dev-bootstrap.service to reinstall it." >&2
  exit 1
fi
exec "$agent_bin" "$@"
EOF
chmod 0755 "$LOCAL_BIN/@AGENT_BIN@"
maybe_chown_dev "$LOCAL_BIN/@AGENT_BIN@"
log_phase "wrapper-written @AGENT_BIN@"
current_bootstrap_phase=wrapper-written
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_BIN@"

if [ ! -x "$AGENT_GLOBAL_BIN" ] || [ "$installed_spec" != "@AGENT_PACKAGE_SPEC@" ]; then
  log_phase "toolchain-install-start @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-install-start
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
  bun install --global "@AGENT_PACKAGE_SPEC@"
  printf '%s\n' '@AGENT_PACKAGE_SPEC@' > "$AGENT_SPEC_MARKER_PATH"
  maybe_chown_dev "$AGENT_SPEC_MARKER_PATH"
  log_phase "toolchain-install-done @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-install-done
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
else
  log_phase "toolchain-cache-hit @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-cache-hit
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
fi

if [ -e "$AGENT_GLOBAL_BIN" ]; then
  maybe_chown_dev "$AGENT_GLOBAL_BIN"
fi

printf '%s\n' '@AGENT_PACKAGE_SPEC@' >"$FIREBREAK_BOOTSTRAP_READY_MARKER"
maybe_chown_dev "$FIREBREAK_BOOTSTRAP_READY_MARKER"
log_phase "wrapper-ready @AGENT_BIN@"
current_bootstrap_phase=wrapper-ready
write_bootstrap_state "$current_bootstrap_phase" "ready" "@AGENT_BIN@"
