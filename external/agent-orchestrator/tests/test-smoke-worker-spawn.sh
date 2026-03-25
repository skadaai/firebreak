set -eu

firebreak_tmp_root=${FIREBREAK_TMPDIR:-${TMPDIR:-/tmp}}/firebreak/tmp
mkdir -p "$firebreak_tmp_root"
smoke_tmp_dir=$(mktemp -d "$firebreak_tmp_root/test-smoke-agent-orchestrator-worker-spawn.XXXXXX")
trap 'rm -rf "$smoke_tmp_dir"' EXIT INT TERM

workspace_dir=$smoke_tmp_dir/workspace
mkdir -p "$workspace_dir"

guest_script=$workspace_dir/firebreak-worker-spawn-check.sh
cat >"$guest_script" <<'EOF'
set -eu

FIREBREAK_BOOTSTRAP_WAIT_TIMEOUT_SECONDS=60 firebreak-bootstrap-wait

spawn_output=$(firebreak worker spawn --kind codex --workspace "$PWD" -- --version)
printf '__SPAWN__%s\n' "$spawn_output"

worker_id=$(SPAWN_OUTPUT="$spawn_output" node -e 'process.stdout.write(JSON.parse(process.env.SPAWN_OUTPUT).worker_id)')
printf '__WORKER_ID__%s\n' "$worker_id"

for _ in $(seq 1 240); do
  show_output=$(firebreak worker show --worker-id "$worker_id")
  status=$(SHOW_OUTPUT="$show_output" node -e 'const data = JSON.parse(process.env.SHOW_OUTPUT); process.stdout.write(String(data.status ?? ""));')
  printf '__STATUS__%s\n' "$status"

  case "$status" in
    exited|stopped)
      exit_code=$(SHOW_OUTPUT="$show_output" node -e 'const data = JSON.parse(process.env.SHOW_OUTPUT); process.stdout.write(String(data.exit_code ?? ""));')
      if [ "$exit_code" != "0" ]; then
        echo "codex worker exited with non-zero code: $exit_code" >&2
        exit 1
      fi

      list_output=$(firebreak worker list)
      printf '__LIST__%s\n' "$list_output"
      if ! printf '%s\n' "$list_output" | grep -F -q "$worker_id"; then
        echo "worker list did not include the spawned codex worker" >&2
        exit 1
      fi

      printf '%s\n' '__WORKER_OK__'
      exit 0
      ;;
  esac

  sleep 1
done

echo "timed out waiting for the spawned codex worker to finish" >&2
exit 1
EOF

set +e
output=$(
  cd "$workspace_dir"
  FIREBREAK_INSTANCE_EPHEMERAL=1 \
    FIREBREAK_VM_MODE=shell \
    AGENT_VM_COMMAND="bash $guest_script" \
    @AGENT_ORCHESTRATOR_BIN@ 2>&1
)
status=$?
set -e

if [ "$status" -ne 0 ]; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator worker-spawn smoke did not complete successfully" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -F -q '__WORKER_OK__'; then
  printf '%s\n' "$output" >&2
  echo "agent-orchestrator worker-spawn smoke did not observe a successful worker lifecycle" >&2
  exit 1
fi

printf '%s\n' "Agent Orchestrator worker spawn smoke test passed"
