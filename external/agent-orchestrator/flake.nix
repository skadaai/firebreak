{
  description = "Firebreak sandbox recipe for ComposioHQ/agent-orchestrator";

  inputs.firebreak.url = "github:skadaai/firebreak";

  outputs = { firebreak, ... }:
    let
      system = "x86_64-linux";
      project = firebreak.lib.${system}.mkPackagedNodeCliArtifacts {
        name = "firebreak-agent-orchestrator";
        displayName = "Agent Orchestrator";
        tagline = "agent-orchestrator cli sandbox";
        packageSpec = "@composio/ao";
        binName = "ao";
        workerBridgeEnabled = true;
        workerKinds = {
          codex = {
            backend = "firebreak";
            package = "firebreak-codex";
            vm_mode = "run";
          };
          claude-code = {
            backend = "firebreak";
            package = "firebreak-claude-code";
            vm_mode = "run";
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
        forwardPorts = [
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
    in {
      nixosConfigurations.firebreak-agent-orchestrator = project.nixosConfiguration;

      packages.${system} = {
        default = project.package;
        firebreak-agent-orchestrator = project.package;
        firebreak-internal-runner-agent-orchestrator = project.runnerPackage;
      };
    };
}
