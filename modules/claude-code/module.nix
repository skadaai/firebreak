moduleArgs@{ pkgs, ... }:
(import ../packaged-agent/module.nix moduleArgs) {
  vmName = "firebreak-claude-code";
  displayName = "Claude Code";
  binName = "claude";
  package = pkgs.claude-code;
  promptCommand = ''claude -p "$FIREBREAK_AGENT_PROMPT"'';
  configSelectorPrefix = "CLAUDE";
  configSubdir = "claude";
  configExports = ''
    export CLAUDE_CONFIG_DIR="$tool_state_dir"
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
  extraEnvironmentPathPackages = with pkgs; [ ripgrep ];
}
