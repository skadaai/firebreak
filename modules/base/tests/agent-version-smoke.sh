set -eu

output=$(
  env \
    -u AGENT_CONFIG \
    -u AGENT_CONFIG_HOST_PATH \
    -u CODEX_CONFIG \
    -u CODEX_CONFIG_HOST_PATH \
    -u CLAUDE_CONFIG \
    -u CLAUDE_CONFIG_HOST_PATH \
    @AGENT_PACKAGE_BIN@ --version 2>&1
)

case "$output" in
  *[0-9].[0-9]* | *[0-9].[0-9].[0-9]*)
    ;;
  *)
    printf '%s\n' "$output" >&2
    echo "@AGENT_DISPLAY_NAME@ version smoke did not print a recognizable version string" >&2
    exit 1
    ;;
esac

printf '%s\n' "$output"
