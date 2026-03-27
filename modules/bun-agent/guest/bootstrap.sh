set -eu

export DEV_HOME=@DEV_HOME@
export HOME="$DEV_HOME"
export BUN_INSTALL="$DEV_HOME/.bun"
export LOCAL_BIN="$DEV_HOME/.local/bin"
export XDG_CONFIG_HOME="$DEV_HOME/.config"
export XDG_CACHE_HOME="$DEV_HOME/.cache"
export XDG_STATE_HOME="$DEV_HOME/.local/state"
export TMPDIR="$XDG_CACHE_HOME/tmp"
export BUN_TMPDIR="$TMPDIR"
export BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/bun/install/cache"
export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$XDG_CACHE_HOME/bun/transpiler"
export PATH="$LOCAL_BIN:$BUN_INSTALL/bin:$PATH"
export AGENT_SPEC_MARKER_DIR="$XDG_STATE_HOME/firebreak-bun-agent"
export AGENT_SPEC_MARKER_PATH="$AGENT_SPEC_MARKER_DIR/@AGENT_BIN@.spec"
export AGENT_GLOBAL_BIN="$BUN_INSTALL/bin/@AGENT_BIN@"
export FIREBREAK_GUEST_STATE_DIR=/run/firebreak-agent
export FIREBREAK_BOOTSTRAP_STATE_PATH="$FIREBREAK_GUEST_STATE_DIR/bootstrap-state.json"
export FIREBREAK_SHARED_BOOTSTRAP_STATE_PATH="@AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json"
export FIREBREAK_BOOTSTRAP_READY_MARKER="@BOOTSTRAP_READY_MARKER@"

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
    cp "$FIREBREAK_BOOTSTRAP_STATE_PATH" "$FIREBREAK_SHARED_BOOTSTRAP_STATE_PATH"
  fi
}

current_bootstrap_phase=init
bootstrap_trap() {
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    rm -f "$FIREBREAK_BOOTSTRAP_READY_MARKER"
    write_bootstrap_state "$current_bootstrap_phase" "error" "bootstrap-exit:$exit_code"
  fi
  exit "$exit_code"
}
trap bootstrap_trap EXIT

log_phase "toolchain-prepare-start @AGENT_DISPLAY_NAME@"
install -d -m 0755 -o @DEV_USER@ -g @DEV_USER@ "$FIREBREAK_GUEST_STATE_DIR"
install -d -m 0755 "$(dirname "$FIREBREAK_BOOTSTRAP_READY_MARKER")"
rm -f "$FIREBREAK_BOOTSTRAP_READY_MARKER"
current_bootstrap_phase=toolchain-prepare-start
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_DISPLAY_NAME@"

install -d -m 0755 -o @DEV_USER@ -g @DEV_USER@ \
  "$BUN_INSTALL/bin" \
  "$LOCAL_BIN" \
  "$TMPDIR" \
  "$BUN_INSTALL_CACHE_DIR" \
  "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" \
  "$XDG_CONFIG_HOME" \
  "$AGENT_SPEC_MARKER_DIR"
log_phase "toolchain-directories-ready @AGENT_DISPLAY_NAME@"
current_bootstrap_phase=toolchain-directories-ready
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_DISPLAY_NAME@"
log_phase "toolchain-ownership-ready @AGENT_DISPLAY_NAME@"
current_bootstrap_phase=toolchain-ownership-ready
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_DISPLAY_NAME@"

cat > "$LOCAL_BIN/@AGENT_BIN@" <<'EOF'
#!/bin/sh
set -eu
agent_bin="${BUN_INSTALL:-$HOME/.bun}/bin/@AGENT_BIN@"
if [ ! -x "$agent_bin" ]; then
  echo "@AGENT_DISPLAY_NAME@ is not installed in $agent_bin" >&2
  echo "Restart dev-bootstrap.service to reinstall it." >&2
  exit 1
fi
exec "$agent_bin" "$@"
EOF
chmod 0755 "$LOCAL_BIN/@AGENT_BIN@"
chown @DEV_USER@:@DEV_USER@ "$LOCAL_BIN/@AGENT_BIN@"
log_phase "wrapper-written @AGENT_BIN@"
current_bootstrap_phase=wrapper-written
write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_BIN@"

installed_spec=""
if [ -r "$AGENT_SPEC_MARKER_PATH" ]; then
  installed_spec=$(cat "$AGENT_SPEC_MARKER_PATH")
fi

if [ ! -x "$AGENT_GLOBAL_BIN" ] || [ "$installed_spec" != "@AGENT_PACKAGE_SPEC@" ]; then
  log_phase "toolchain-install-start @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-install-start
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
  bun install --global "@AGENT_PACKAGE_SPEC@"
  printf '%s\n' '@AGENT_PACKAGE_SPEC@' > "$AGENT_SPEC_MARKER_PATH"
  chown @DEV_USER@:@DEV_USER@ "$AGENT_SPEC_MARKER_PATH"
  log_phase "toolchain-install-done @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-install-done
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
else
  log_phase "toolchain-cache-hit @AGENT_PACKAGE_SPEC@"
  current_bootstrap_phase=toolchain-cache-hit
  write_bootstrap_state "$current_bootstrap_phase" "running" "@AGENT_PACKAGE_SPEC@"
fi

if [ -e "$AGENT_GLOBAL_BIN" ]; then
  chown @DEV_USER@:@DEV_USER@ "$AGENT_GLOBAL_BIN"
fi

log_phase "wrapper-ready @AGENT_BIN@"
current_bootstrap_phase=wrapper-ready
write_bootstrap_state "$current_bootstrap_phase" "ready" "@AGENT_BIN@"
printf '%s\n' '@AGENT_PACKAGE_SPEC@' >"$FIREBREAK_BOOTSTRAP_READY_MARKER"
chown @DEV_USER@:@DEV_USER@ "$FIREBREAK_BOOTSTRAP_READY_MARKER"
