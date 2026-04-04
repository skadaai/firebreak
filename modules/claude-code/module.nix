moduleArgs@{ pkgs, ... }:
(import ../bun-agent/module.nix moduleArgs) {
  vmName = "firebreak-claude-code";
  displayName = "Claude Code";
  binName = "claude";
  packageSpec = "@anthropic-ai/claude-code@latest";
  promptCommand = ''claude -p "$FIREBREAK_AGENT_PROMPT"'';
  configSelectorPrefix = "CLAUDE";
  configSubdir = "claude";
  configExports = ''
    export CLAUDE_CONFIG_DIR="$agent_config_dir"
  '';
  credentialFileBindings = [
    {
      slotPath = ".credentials.json";
      runtimePath = ".credentials.json";
    }
  ];
  credentialEnvBindings = [
    {
      slotPath = "ANTHROPIC_API_KEY";
      envVar = "ANTHROPIC_API_KEY";
    }
  ];
  credentialLoginArgs = [ "auth" "login" ];
  credentialLoginMaterialization = "slot-root";
  extraSystemPackages = with pkgs; [ ripgrep ];
}
