set -eu

state_dir=${FIREBREAK_VALIDATION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/validation}
command=${1:-}
suite_name=""
host_os=$(uname -s 2>/dev/null || printf '%s' unknown)
host_arch=$(uname -m 2>/dev/null || printf '%s' unknown)

usage() {
  cat <<'EOF' >&2
usage: firebreak internal validate run SUITE [--state-dir PATH]

Named suites:
  test-smoke-codex
  test-smoke-codex-version
  test-smoke-claude-code
@CLOUD_SUITE_USAGE@
EOF
  exit 1
}

json_escape() {
  value=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  value=$(printf '%s' "$value" | tr '\n' ' ')
  printf '%s' "$value"
}

emit_summary() {
  cat >"$summary_path" <<EOF
{
  "suite": "$(json_escape "$suite_name")",
  "result": "$(json_escape "$result")",
  "required_capabilities": ["$(json_escape "$required_capability")"],
  "missing_capability": $(if [ -n "$missing_capability" ]; then printf '"%s"' "$(json_escape "$missing_capability")"; else printf 'null'; fi),
  "command": "$(json_escape "$suite_command")",
  "run_dir": "$(json_escape "$run_dir")",
  "stdout_path": "$(json_escape "$stdout_path")",
  "stderr_path": "$(json_escape "$stderr_path")",
  "exit_code_path": "$(json_escape "$exit_code_path")",
  "started_at": "$(json_escape "$started_at")",
  "finished_at": "$(json_escape "$finished_at")",
  "exit_code": $exit_code
}
EOF
}

case "$command" in
  run)
    shift
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak internal validate subcommand: $command" >&2
    usage
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir)
      state_dir=$2
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      if [ -n "$suite_name" ]; then
        usage
      fi
      suite_name=$1
      shift
      ;;
  esac
done

if [ -z "$suite_name" ]; then
  usage
fi

case "$state_dir" in
  /*) ;;
  *)
    echo "validation state dir must be absolute: $state_dir" >&2
    exit 1
    ;;
esac

required_capability="local-hypervisor"
missing_capability=""

case "$suite_name" in
  test-smoke-codex)
    suite_command="@CODEX_SMOKE_BIN@"
    ;;
  test-smoke-codex-version)
    suite_command="@CODEX_VERSION_BIN@"
    ;;
  test-smoke-claude-code)
    suite_command="@CLAUDE_SMOKE_BIN@"
    ;;
@CLOUD_SUITE_CASE@
  *)
    echo "unknown validation suite: $suite_name" >&2
    usage
    ;;
esac

if [ -n "${FIREBREAK_VALIDATION_FORCE_BLOCKED_REASON:-}" ]; then
  missing_capability=$FIREBREAK_VALIDATION_FORCE_BLOCKED_REASON
else
  case "$host_os:$host_arch" in
    Linux:*)
      required_capability="cloud-hypervisor-local-host"
      if ! [ -r /dev/kvm ]; then
        missing_capability="kvm-unavailable"
      elif ! [ -w /dev/kvm ]; then
        missing_capability="kvm-not-writable"
      elif ! [ -r /proc/sys/net/ipv4/ip_forward ] || [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        missing_capability="ip-forward-disabled"
      elif ! command -v sudo >/dev/null 2>&1; then
        missing_capability="sudo-missing"
      elif ! command -v ip >/dev/null 2>&1; then
        missing_capability="ip-tool-missing"
      elif ! command -v iptables >/dev/null 2>&1; then
        missing_capability="iptables-tool-missing"
      elif ! sudo -n "$(command -v ip)" link show >/dev/null 2>&1; then
        missing_capability="sudo-networking-denied"
      elif ! sudo -n "$(command -v iptables)" -w -L >/dev/null 2>&1; then
        missing_capability="sudo-firewall-denied"
      fi
      ;;
    Darwin:arm64|Darwin:aarch64)
      required_capability="apple-silicon-vfkit"
      ;;
    Darwin:*)
      required_capability="apple-silicon-vfkit"
      missing_capability="unsupported-intel-mac"
      ;;
    *)
      missing_capability="unsupported-host-platform"
      ;;
  esac
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
run_id=${timestamp}-${suite_name}
run_dir=$state_dir/runs/$run_id
stdout_path=$run_dir/stdout.log
stderr_path=$run_dir/stderr.log
exit_code_path=$run_dir/exit_code
summary_path=$run_dir/summary.json
mkdir -p "$run_dir"

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
result="blocked"
exit_code=0

if [ -n "$missing_capability" ]; then
  printf 'blocked: missing capability: %s\n' "$missing_capability" >"$stderr_path"
  printf '%s\n' 0 >"$exit_code_path"
  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  emit_summary
  cat "$summary_path"
  exit 0
fi

result="failed"
set +e
"$suite_command" >"$stdout_path" 2>"$stderr_path"
exit_code=$?
set -e
printf '%s\n' "$exit_code" >"$exit_code_path"

if [ "$exit_code" -eq 0 ]; then
  result="passed"
fi

finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
emit_summary
cat "$summary_path"

if [ "$result" = "passed" ]; then
  exit 0
fi

exit "$exit_code"
