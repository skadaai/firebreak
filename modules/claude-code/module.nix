moduleArgs@{ pkgs, ... }:
(import ../bun-agent/module.nix moduleArgs) {
  vmName = "firebreak-claude-code";
  displayName = "Claude Code";
  binName = "claude";
  packageSpec = "@anthropic-ai/claude-code@latest";
  promptCommand = ''claude -p "$FIREBREAK_AGENT_PROMPT"'';
  configDirName = ".claude";
  configExports = ''
    export CLAUDE_CONFIG_DIR="$agent_config_dir"
  '';
  extraSystemPackages = with pkgs; [ ripgrep ];
}
