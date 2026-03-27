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

log_phase() {
  printf '[firebreak-bootstrap] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
}

log_phase "toolchain-prepare-start @AGENT_DISPLAY_NAME@"

install -d -m 0755 -o @DEV_USER@ -g @DEV_USER@ \
  "$BUN_INSTALL/bin" \
  "$LOCAL_BIN" \
  "$TMPDIR" \
  "$BUN_INSTALL_CACHE_DIR" \
  "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" \
  "$XDG_CONFIG_HOME" \
  "$AGENT_SPEC_MARKER_DIR"
log_phase "toolchain-directories-ready @AGENT_DISPLAY_NAME@"
log_phase "toolchain-ownership-ready @AGENT_DISPLAY_NAME@"

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

installed_spec=""
if [ -r "$AGENT_SPEC_MARKER_PATH" ]; then
  installed_spec=$(cat "$AGENT_SPEC_MARKER_PATH")
fi

if [ ! -x "$AGENT_GLOBAL_BIN" ] || [ "$installed_spec" != "@AGENT_PACKAGE_SPEC@" ]; then
  log_phase "toolchain-install-start @AGENT_PACKAGE_SPEC@"
  bun install --global "@AGENT_PACKAGE_SPEC@"
  printf '%s\n' '@AGENT_PACKAGE_SPEC@' > "$AGENT_SPEC_MARKER_PATH"
  chown @DEV_USER@:@DEV_USER@ "$AGENT_SPEC_MARKER_PATH"
  log_phase "toolchain-install-done @AGENT_PACKAGE_SPEC@"
else
  log_phase "toolchain-cache-hit @AGENT_PACKAGE_SPEC@"
fi

if [ -e "$AGENT_GLOBAL_BIN" ]; then
  chown @DEV_USER@:@DEV_USER@ "$AGENT_GLOBAL_BIN"
fi

log_phase "wrapper-ready @AGENT_BIN@"
