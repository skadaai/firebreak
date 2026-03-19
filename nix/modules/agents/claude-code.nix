moduleArgs@{ pkgs, ... }:
(import ./mk-bun-agent.nix moduleArgs) {
  vmName = "firebreak-claude-code";
  displayName = "Claude Code";
  binName = "claude";
  packageSpec = "@anthropic-ai/claude-code@latest";
  configDirName = ".claude";
  configExports = ''
    export CLAUDE_CONFIG_DIR="$agent_config_dir"
  '';
  extraSystemPackages = with pkgs; [ ripgrep ];
}
