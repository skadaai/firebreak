{ pkgs, project, testProject, firebreakBin }:
let
  packageBin = "${testProject.package}/bin/firebreak-vibe-kanban";
  workerInteractiveCodexSmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-vibe-kanban-worker-interactive-codex";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      python3
    ];
    text = builtins.replaceStrings
      [ "@VIBE_KANBAN_BIN@" "@FIREBREAK_BIN@" ]
      [ packageBin firebreakBin ]
      (builtins.readFile ./tests/test-smoke-worker-interactive-codex.sh);
  };
  workerInteractiveClaudeSmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-vibe-kanban-worker-interactive-claude";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      python3
    ];
    text = builtins.replaceStrings
      [ "@VIBE_KANBAN_BIN@" "@FIREBREAK_BIN@" ]
      [ packageBin firebreakBin ]
      (builtins.readFile ./tests/test-smoke-worker-interactive-claude.sh);
  };
in {
  packages = {
    firebreak-test-smoke-vibe-kanban-worker-interactive-codex = workerInteractiveCodexSmoke;
    firebreak-test-smoke-vibe-kanban-worker-interactive-claude = workerInteractiveClaudeSmoke;
  };

  checks = { };
}
