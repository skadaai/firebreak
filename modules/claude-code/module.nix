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
      format = "json";
      runtimePath = ".credentials.json";
    }
  ];
  credentialEnvBindings = [
    {
      envVar = "ANTHROPIC_API_KEY";
    }
  ];
  credentialLoginArgs = [ "auth" "login" ];
  credentialLoginMaterialization = "slot-root";
  extraEnvironmentPackages = with pkgs; [ ripgrep ];
}
