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

echo "Preparing persistent Codex tools..."

mkdir -p \
  "$BUN_INSTALL/bin" \
  "$LOCAL_BIN" \
  "$TMPDIR" \
  "$BUN_INSTALL_CACHE_DIR" \
  "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" \
  "$XDG_CONFIG_HOME" \
  "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME"
chown -R @DEV_USER@:@DEV_USER@ "$DEV_HOME"

cat > "$LOCAL_BIN/codex" <<'EOF'
#!/bin/sh
set -eu
exec bunx --silent --package @openai/codex@latest codex "$@"
EOF
chmod 0755 "$LOCAL_BIN/codex"

# Remove stale global installs so the wrapper is the only Codex entrypoint.
rm -f "$BUN_INSTALL/bin/codex"

echo "Validating Bun-managed Codex CLI..."
if ! codex --version >/dev/null 2>&1; then
  echo "Codex CLI validation failed." >&2
  exit 1
fi

chown -R @DEV_USER@:@DEV_USER@ "$DEV_HOME"
