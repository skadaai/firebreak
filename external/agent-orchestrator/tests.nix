{ pkgs, project, testProject }:
let
  packageBin = "${testProject.package}/bin/firebreak-agent-orchestrator";

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
in {
  packages = {
    firebreak-test-smoke-agent-orchestrator-worker-proxy = workerProxySmoke;
    firebreak-test-smoke-agent-orchestrator-worker-spawn = workerSpawnSmoke;
  };

  checks = {
    firebreak-test-smoke-agent-orchestrator-worker-proxy = workerProxySmoke;
    firebreak-test-smoke-agent-orchestrator-worker-spawn = workerSpawnSmoke;
  };
}
