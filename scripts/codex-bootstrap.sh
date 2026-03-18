set -eu

export DEV_HOME=@DEV_HOME@
export HOME="$DEV_HOME"
export BUN_INSTALL="$DEV_HOME/.bun"
export XDG_CONFIG_HOME="$DEV_HOME/.config"
export XDG_CACHE_HOME="$DEV_HOME/.cache"
export XDG_STATE_HOME="$DEV_HOME/.local/state"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "Preparing persistent Codex tools..."

mkdir -p \
  "$BUN_INSTALL/bin" \
  "$XDG_CONFIG_HOME" \
  "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME"
chown -R @DEV_USER@:@DEV_USER@ "$DEV_HOME"
if ! [ -x "$BUN_INSTALL/bin/codex" ]; then
  echo "Installing Codex CLI into persistent storage..."
  bun install --global @openai/codex
  chown -R @DEV_USER@:@DEV_USER@ "$DEV_HOME"
else
  echo "Codex CLI already present."
fi
