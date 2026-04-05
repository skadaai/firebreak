#!/usr/bin/env bash
set -eu

export DEV_HOME=@DEV_HOME@
tool_home=$DEV_HOME
if [ -d @AGENT_TOOLS_MOUNT@ ]; then
  tool_home=@AGENT_TOOLS_MOUNT@
fi

export BUN_INSTALL="$tool_home/.bun"
export LOCAL_BIN="$tool_home/.local/bin"
export XDG_STATE_HOME="$tool_home/.local/state"
export AGENT_SPEC_MARKER_PATH="$XDG_STATE_HOME/firebreak-bun-agent/@AGENT_BIN@.spec"
export AGENT_GLOBAL_BIN="$BUN_INSTALL/bin/@AGENT_BIN@"
export FIREBREAK_BOOTSTRAP_READY_MARKER="@BOOTSTRAP_READY_MARKER@"

agent_wrapper_path="$LOCAL_BIN/@AGENT_BIN@"
installed_spec=""
if [ -r "$AGENT_SPEC_MARKER_PATH" ]; then
  installed_spec=$(cat "$AGENT_SPEC_MARKER_PATH")
fi

if [ -x "$AGENT_GLOBAL_BIN" ] \
  && [ -x "$agent_wrapper_path" ] \
  && [ "$installed_spec" = "@AGENT_PACKAGE_SPEC@" ] \
  && [ -r "$FIREBREAK_BOOTSTRAP_READY_MARKER" ]; then
  exit 1
fi

exit 0
