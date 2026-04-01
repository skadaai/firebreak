{
  description = "Firebreak sandbox recipe for ComposioHQ/agent-orchestrator";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.firebreak.url = "github:skadaai/firebreak";
  inputs.firebreak.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { firebreak, nixpkgs, ... }:
    let
      mkProject = system: forwardPorts:
        firebreak.lib.${system}.mkPackagedNodeCliArtifacts {
          name = "firebreak-agent-orchestrator";
          displayName = "Agent Orchestrator";
          tagline = "agent-orchestrator cli sandbox";
          packageSpec = "@composio/ao";
          binName = "ao";
          defaultWorkerMode = "vm";
          workerProxies = {
            codex = {
              kind = "codex";
              backend = "firebreak";
              package = "firebreak-codex";
              vm_mode = "run";
              max_instances = 4;
              versionOutput = "codex firebreak-worker wrapper";
            };
            claude = {
              kind = "claude-code";
              backend = "firebreak";
              package = "firebreak-claude-code";
              vm_mode = "run";
              max_instances = 2;
              versionOutput = "claude firebreak-worker wrapper";
            };
          };
          runtimePackages = pkgs: with pkgs; [
            git
            gh
            pnpm
            tmux
          ];
          launchEnvironment = {
            TERMINAL_PORT = "14800";
            DIRECT_TERMINAL_PORT = "14801";
          };
          inherit forwardPorts;
          postInstallScript = ''
            # fix for https://github.com/ComposioHQ/agent-orchestrator/issues/640
            ao_root="$npm_config_prefix/lib/node_modules/@composio/ao"
            ao_web_dir=$(node -e "const { dirname } = require(\"path\"); const root = process.argv[1]; const pkg = require.resolve(\"@composio/ao-web/package.json\", { paths: [root] }); process.stdout.write(dirname(pkg));" "$ao_root")
            ao_core_dir="$ao_root/node_modules/@composio/ao-core"

            if ! [ -d "$ao_core_dir" ]; then
              echo "expected @composio/ao-core at $ao_core_dir after npm install" >&2
              exit 1
            fi

            mkdir -p "$ao_web_dir/node_modules/@composio"
            ln -sfn "$ao_core_dir" "$ao_web_dir/node_modules/@composio/ao-core"
          '';
          launchCommand = "ao start .";
          extraShellInit = ''
            alias ao-start='project-launch'
          '';
        };
    in
    firebreak.recipeLib.mkPackagedNodeCliFlakeOutputs {
      inherit firebreak nixpkgs mkProject;
      testsModule = ./tests.nix;
      nixosConfigurationName = "firebreak-agent-orchestrator";
      packageName = "firebreak-agent-orchestrator";
      runnerPackageName = "firebreak-internal-runner-agent-orchestrator";
      defaultForwardPorts = [
        {
          from = "host";
          proto = "tcp";
          host.address = "127.0.0.1";
          host.port = 3000;
          guest.port = 3000;
        }
        {
          from = "host";
          proto = "tcp";
          host.address = "127.0.0.1";
          host.port = 14800;
          guest.port = 14800;
        }
        {
          from = "host";
          proto = "tcp";
          host.address = "127.0.0.1";
          host.port = 14801;
          guest.port = 14801;
        }
      ];
    };
}
