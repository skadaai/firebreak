set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-agent-orchestrator-worker-interactive.XXXXXX")

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$status" -eq 0 ]; then
    rm -rf "$smoke_tmp_dir"
  else
    printf '%s\n' "preserved interactive AO smoke artifacts: $smoke_tmp_dir" >&2
  fi
  exit "$status"
}

trap cleanup EXIT INT TERM

session_log=$smoke_tmp_dir/session.log

set +e
env \
  FIREBREAK_INSTANCE_EPHEMERAL=1 \
  FIREBREAK_VM_MODE=shell \
  AGENT_VM_COMMAND='FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS=60 firebreak-bootstrap-wait && codex' \
  timeout 180 sh -c '
    (
      sleep 20
      printf "\003"
    ) | script -qefc "@AGENT_ORCHESTRATOR_BIN@" /dev/null
  ' >"$session_log" 2>&1
status=$?
set -e

cat "$session_log"

if [ "$status" -eq 124 ]; then
  echo "interactive Agent Orchestrator smoke timed out waiting for attached codex startup" >&2
  exit 1
fi

if ! grep -F -q 'Welcome to Skada Firebreak - reliable isolation for high-trust automation' "$session_log"; then
  echo "interactive Agent Orchestrator smoke did not surface sibling worker welcome output" >&2
  exit 1
fi

if ! grep -F -q '[ vm: firebreak-codex | mode: agent-attach-exec | workspace:' "$session_log"; then
  echo "interactive Agent Orchestrator smoke did not surface the attached codex worker banner" >&2
  exit 1
fi

printf '%s\n' "Agent Orchestrator interactive codex smoke test passed"
