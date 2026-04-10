moduleArgs@{ pkgs, ... }:
(import ../packaged-agent/module.nix moduleArgs) {
  vmName = "firebreak-codex";
  displayName = "Codex";
  binName = "codex";
  package = pkgs.codex;
  promptCommand = ''codex exec "$FIREBREAK_AGENT_PROMPT"'';
  configSelectorPrefix = "CODEX";
  configSubdir = "codex";
  configExports = ''
    export CODEX_HOME="$tool_state_dir"
    export CODEX_CONFIG_DIR="$tool_state_dir"
  '';
  credentialFileBindings = [
    {
      format = "json";
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
