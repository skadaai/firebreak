moduleArgs@{ pkgs, ... }:
(import ../bun-agent/module.nix moduleArgs) {
  vmName = "firebreak-codex";
  displayName = "Codex";
  binName = "codex";
  packageSpec = "@openai/codex@latest";
  promptCommand = ''codex exec "$FIREBREAK_AGENT_PROMPT"'';
  configSelectorPrefix = "CODEX";
  configSubdir = "codex";
  configExports = ''
    export CODEX_HOME="$tool_state_dir"
    export CODEX_CONFIG_DIR="$tool_state_dir"
  '';
  credentialFileBindings = [
    {
      runtimePath = "auth.json";
    }
  ];
  credentialEnvBindings = [
    {
      envVar = "OPENAI_API_KEY";
    }
  ];
  credentialLoginArgs = [ "login" ];
  credentialLoginMaterialization = "slot-root";
}
