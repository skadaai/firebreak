#!/usr/bin/env bash
set -eu

set +e
output=$(
  FIREBREAK_INSTANCE_EPHEMERAL=1 \
    FIREBREAK_LAUNCH_MODE=shell \
    AGENT_VM_COMMAND='FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS=60 firebreak-bootstrap-wait && command -v firebreak-bootstrap-wait && command -v ao && command -v codex && FIREBREAK_WRAPPER_INFO=1 codex && command -v claude && FIREBREAK_WRAPPER_INFO=1 claude' \
    @AGENT_ORCHESTRATOR_BIN@ 2>&1
)
status=$?
set -e

if [ "$status" -ne 0 ]; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator smoke command did not complete successfully" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q "firebreak-bootstrap-wait"; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator smoke did not resolve firebreak-bootstrap-wait in PATH" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q "/.local/bin/ao"; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator smoke did not resolve ao from the packaged node-cli install" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q '"command": "codex"'; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator smoke did not expose the Firebreak worker proxy wrapper" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q '"command": "claude"'; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator smoke did not expose the Claude Firebreak worker proxy wrapper" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q '"resolved_mode": "vm"'; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator smoke did not report vm wrapper mode" >&2
  exit 1
fi

printf '%s\n' "Agent Orchestrator worker proxy smoke test passed"
