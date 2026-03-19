moduleArgs@{ pkgs, ... }:
(import ./mk-bun-agent.nix moduleArgs) {
  vmName = "firebreak-codex";
  displayName = "Codex";
  binName = "codex";
  packageSpec = "@openai/codex@latest";
  configDirName = ".codex";
  configExports = ''
    export CODEX_HOME="$agent_config_dir"
    export CODEX_CONFIG_DIR="$agent_config_dir"
  '';
}
