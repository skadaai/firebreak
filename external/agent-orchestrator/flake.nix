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
        runtimePackages = pkgs: with pkgs; [
          git
          gh
          pnpm
          tmux
        ];
        bootstrapPackages = pkgs: with pkgs; [
          gcc
          gnumake
          pkg-config
          python3
        ];
        launchEnvironment = {
          # ao start does not consume PORT as an input; dashboard port comes from
          # config.port in agent-orchestrator.yaml.
          # TERMINAL_PORT = "14800";
          # DIRECT_TERMINAL_PORT = "14801";
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
          npm install --global --omit=dev \
            "@anthropic-ai/claude-code@latest" \
            "@openai/codex@latest"
          npm install --prefix "$ao_web_dir" --no-save --omit=dev node-pty

          if ! [ -d "$ao_core_dir" ]; then
            echo "expected @composio/ao-core at $ao_core_dir after npm install" >&2
            exit 1
          fi

          mkdir -p "$ao_web_dir/node_modules/@composio"
          ln -sfn "$ao_core_dir" "$ao_web_dir/node_modules/@composio/ao-core"
        '';
        multiAgentConfig = {
          enable = true;
          agents = {
            codex = {
              displayName = "Codex";
              selectorPrefix = "CODEX";
              configSubdir = "codex";
              configEnvExports = ''
                export CODEX_HOME="$config_dir"
                export CODEX_CONFIG_DIR="$config_dir"
              '';
            };
            claude = {
              displayName = "Claude Code";
              selectorPrefix = "CLAUDE";
              configSubdir = "claude";
              configEnvExports = ''
                export CLAUDE_CONFIG_DIR="$config_dir"
              '';
            };
          };
        };
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
