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
    export CODEX_HOME="$agent_config_dir"
    export CODEX_CONFIG_DIR="$agent_config_dir"
  '';
}
