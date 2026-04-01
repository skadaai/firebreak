{ pkgs, project, testProject, firebreakBin }:
let
  packageBin = "${testProject.package}/bin/firebreak-agent-orchestrator";
  mkExecutableCheck = { name, package }:
    pkgs.runCommand name {
      nativeBuildInputs = [ package ];
    } ''
      ${package}/bin/${name}
      touch "$out"
    '';

  workerProxySmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-agent-orchestrator-worker-proxy";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
    ];
    text = builtins.replaceStrings
      [ "@AGENT_ORCHESTRATOR_BIN@" ]
      [ packageBin ]
      (builtins.readFile ./tests/test-smoke-worker-proxy.sh);
  };

  workerSpawnSmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-agent-orchestrator-worker-spawn";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
    ];
    text = builtins.replaceStrings
      [ "@AGENT_ORCHESTRATOR_BIN@" ]
      [ packageBin ]
      (builtins.readFile ./tests/test-smoke-worker-spawn.sh);
  };

  workerInteractiveSmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-agent-orchestrator-worker-interactive";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      python3
    ];
    text = builtins.replaceStrings
      [ "@AGENT_ORCHESTRATOR_BIN@" "@FIREBREAK_BIN@" ]
      [ packageBin firebreakBin ]
      (builtins.readFile ./tests/test-smoke-worker-interactive.sh);
  };

  workerInteractiveClaudeSmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-agent-orchestrator-worker-interactive-claude";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      python3
    ];
    text = builtins.replaceStrings
      [ "@AGENT_ORCHESTRATOR_BIN@" "@FIREBREAK_BIN@" ]
      [ packageBin firebreakBin ]
      (builtins.readFile ./tests/test-smoke-worker-interactive-claude.sh);
  };

  workerInteractiveClaudeExitSmoke = pkgs.writeShellApplication {
    name = "firebreak-test-smoke-agent-orchestrator-worker-interactive-claude-exit";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      python3
    ];
    text = builtins.replaceStrings
      [ "@AGENT_ORCHESTRATOR_BIN@" "@FIREBREAK_BIN@" ]
      [ packageBin firebreakBin ]
      (builtins.readFile ./tests/test-smoke-worker-interactive-claude-exit.sh);
  };
in {
  packages = {
    firebreak-test-smoke-agent-orchestrator-worker-proxy = workerProxySmoke;
    firebreak-test-smoke-agent-orchestrator-worker-spawn = workerSpawnSmoke;
    firebreak-test-smoke-agent-orchestrator-worker-interactive = workerInteractiveSmoke;
    firebreak-test-smoke-agent-orchestrator-worker-interactive-claude = workerInteractiveClaudeSmoke;
    firebreak-test-smoke-agent-orchestrator-worker-interactive-claude-exit = workerInteractiveClaudeExitSmoke;
  };

  checks = {
    firebreak-test-smoke-agent-orchestrator-worker-proxy = mkExecutableCheck {
      name = "firebreak-test-smoke-agent-orchestrator-worker-proxy";
      package = workerProxySmoke;
    };
    firebreak-test-smoke-agent-orchestrator-worker-spawn = mkExecutableCheck {
      name = "firebreak-test-smoke-agent-orchestrator-worker-spawn";
      package = workerSpawnSmoke;
    };
    firebreak-test-smoke-agent-orchestrator-worker-interactive = mkExecutableCheck {
      name = "firebreak-test-smoke-agent-orchestrator-worker-interactive";
      package = workerInteractiveSmoke;
    };
    firebreak-test-smoke-agent-orchestrator-worker-interactive-claude = mkExecutableCheck {
      name = "firebreak-test-smoke-agent-orchestrator-worker-interactive-claude";
      package = workerInteractiveClaudeSmoke;
    };
    firebreak-test-smoke-agent-orchestrator-worker-interactive-claude-exit = mkExecutableCheck {
      name = "firebreak-test-smoke-agent-orchestrator-worker-interactive-claude-exit";
      package = workerInteractiveClaudeExitSmoke;
    };
  };
}
