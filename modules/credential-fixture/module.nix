{ lib, pkgs, ... }:
let
  credentialFixtureScript = ''
      set -eu

      fixture_home=''${FIXTURE_HOME:-''${AGENT_CONFIG_DIR:-$HOME/.firebreak/credential-fixture}}
      fixture_name=''${FIXTURE_NAME:-credential-fixture}

      case "''${1:-status}" in
        status)
          shift
          mkdir -p "$fixture_home"
          printf 'FIXTURE_NAME=%s\n' "$fixture_name"
          printf 'FIXTURE_HOME=%s\n' "$fixture_home"
          if [ -r "$fixture_home/auth.json" ]; then
            printf 'AUTH_JSON=%s\n' "$(cat "$fixture_home/auth.json")"
          fi
          printf 'API_KEY=%s\n' "''${FIXTURE_API_KEY:-}"
          if [ -n "''${FIXTURE_KEY_HELPER:-}" ]; then
            printf 'HELPER_VALUE=%s\n' "$("$FIXTURE_KEY_HELPER")"
          fi
          printf '%s\n' 'status' >>"$fixture_home/history.log"
          ;;
        login)
          shift
          mkdir -p "$fixture_home"
          printf '%s\n' "''${1:-fixture-login-token}" >"$fixture_home/auth.json"
          printf 'FIXTURE_NAME=%s\n' "$fixture_name"
          printf 'LOGIN_HOME=%s\n' "$fixture_home"
          ;;
        rotate-auth)
          shift
          mkdir -p "$fixture_home"
          printf '%s\n' "''${1:-fixture-rotated-token}" >"$fixture_home/auth.json"
          printf 'FIXTURE_NAME=%s\n' "$fixture_name"
          printf 'ROTATED_HOME=%s\n' "$fixture_home"
          ;;
        *)
          printf '%s\n' "unsupported credential-fixture command: $1" >&2
          exit 1
          ;;
      esac
    '';
  credentialFixture = pkgs.writeShellApplication {
    name = "credential-fixture";
    runtimeInputs = with pkgs; [ coreutils ];
    text = credentialFixtureScript;
  };
  credentialFixturePeer = pkgs.writeShellApplication {
    name = "credential-fixture-peer";
    runtimeInputs = with pkgs; [ coreutils ];
    text = credentialFixtureScript;
  };
in {
  config = {
    agentVm = {
      name = lib.mkDefault "firebreak-credential-fixture";
      agentCommand = "credential-fixture";
      sharedAgentConfig = {
        enable = true;
        agents.credential-fixture = {
          displayName = "Credential Fixture";
          selectorPrefix = "FIXTURE";
          realBinPath = lib.getExe credentialFixture;
          configSubdir = "credential-fixture";
          configEnvExports = ''
            export FIXTURE_NAME="credential-fixture"
            export FIXTURE_HOME="$agent_config_dir"
          '';
          credentials = {
            slotSubdir = "credential-fixture";
            fileBindings = [
              {
                slotPath = "auth.json";
                runtimePath = "auth.json";
              }
            ];
            envBindings = [
              {
                slotPath = "FIXTURE_API_KEY";
                envVar = "FIXTURE_API_KEY";
              }
            ];
            helperBindings = [
              {
                slotPath = "FIXTURE_HELPER_KEY";
                helperName = "fixture-key-helper";
                envVar = "FIXTURE_KEY_HELPER";
              }
            ];
            loginArgs = [ "login" ];
            loginMaterialization = "slot-root";
          };
        };
        agents.credential-fixture-peer = {
          displayName = "Credential Fixture Peer";
          selectorPrefix = "PEER";
          realBinName = "credential-fixture-peer";
          realBinPath = lib.getExe credentialFixturePeer;
          configSubdir = "credential-fixture-peer";
          configEnvExports = ''
            export FIXTURE_NAME="credential-fixture-peer"
            export FIXTURE_HOME="$agent_config_dir"
          '';
          credentials = {
            slotSubdir = "credential-fixture-peer";
            fileBindings = [
              {
                slotPath = "auth.json";
                runtimePath = "auth.json";
              }
            ];
            envBindings = [
              {
                slotPath = "FIXTURE_API_KEY";
                envVar = "FIXTURE_API_KEY";
              }
            ];
            helperBindings = [
              {
                slotPath = "FIXTURE_HELPER_KEY";
                helperName = "fixture-peer-key-helper";
                envVar = "FIXTURE_KEY_HELPER";
              }
            ];
            loginArgs = [ "login" ];
            loginMaterialization = "slot-root";
          };
        };
      };
      sharedCredentialSlots.enable = true;
      extraSystemPackages = [
        credentialFixture
        credentialFixturePeer
      ];
      bootstrapScript = null;
    };

    networking.firewall.enable = false;
  };
}
