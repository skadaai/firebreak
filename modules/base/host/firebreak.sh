set -eu

command=${1:-}

@FIREBREAK_PROJECT_CONFIG_LIB@
@FIREBREAK_INIT_FUNCTIONS@
@FIREBREAK_DOCTOR_FUNCTIONS@

vms_usage() {
  cat <<'EOF' >&2
usage:
  firebreak vms [--json]
EOF
  exit "${1:-0}"
}

run_usage() {
  cat <<'EOF' >&2
usage:
  firebreak run <vm> [--shell] [-- <vm args...>]
EOF
  exit "${1:-0}"
}

firebreak_vms_command() {
  vms_output=text

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        vms_output=json
        shift
        ;;
      ""|--help|-h|help)
        vms_usage 0
        ;;
      *)
        vms_usage 1
        ;;
    esac
  done

  if [ "$vms_output" = "json" ]; then
    cat <<'EOF'
[
  {
    "name": "codex",
    "description": "Codex local Firebreak VM"
  },
  {
    "name": "claude-code",
    "description": "Claude Code local Firebreak VM"
  }
]
EOF
    return 0
  fi

  cat <<'EOF'
Available Firebreak VMs

  codex        Codex local Firebreak VM
  claude-code  Claude Code local Firebreak VM

Examples:
  firebreak run codex
  firebreak run codex --shell
  firebreak run claude-code -- --help
EOF
}

firebreak_run_command() {
  vm_name=${1:-}
  [ -n "$vm_name" ] || run_usage 1

  case "$vm_name" in
    --help|-h|help)
      run_usage 0
      ;;
  esac
  shift

  requested_vm_mode=${FIREBREAK_VM_MODE:-}

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --shell)
        requested_vm_mode=shell
        shift
        ;;
      --)
        shift
        break
        ;;
      --help|-h|help)
        run_usage 0
        ;;
      -*)
        echo "unknown firebreak run option: $1" >&2
        run_usage 1
        ;;
      *)
        break
        ;;
    esac
  done

  case "$vm_name" in
    codex)
      if [ -n "$requested_vm_mode" ]; then
        exec env FIREBREAK_VM_MODE="$requested_vm_mode" @CODEX_BIN@ "$@"
      else
        exec @CODEX_BIN@ "$@"
      fi
      ;;
    claude-code)
      if [ -n "$requested_vm_mode" ]; then
        exec env FIREBREAK_VM_MODE="$requested_vm_mode" @CLAUDE_CODE_BIN@ "$@"
      else
        exec @CLAUDE_CODE_BIN@ "$@"
      fi
      ;;
    *)
      echo "unknown Firebreak VM: $vm_name" >&2
      echo "run 'firebreak vms' to list available VMs" >&2
      exit 1
      ;;
  esac
}

usage() {
  cat <<'EOF'
Skada Firebreak

usage:
  firebreak init [--force] [--stdout] [--interactive] [--non-interactive]
  firebreak doctor [--verbose] [--json]
  firebreak vms [--json]
  firebreak run <vm> [--shell] [-- <vm args...>]
  firebreak internal <subcommand> ...

Available commands:
  init        Interactively write Firebreak project defaults
  doctor      Explain resolved config and launch readiness
  vms         List the public Firebreak VM workloads
  run         Launch a public Firebreak VM workload
  internal    Internal plumbing for Firebreak's self development by agents and automation

Other human-facing commands remain reserved until they have clear user value and intuitive UX.
EOF
}

case "$command" in
  init)
    shift
    firebreak_init_command "$@"
    ;;
  doctor)
    shift
    firebreak_doctor_command "$@"
    ;;
  vms)
    shift
    firebreak_vms_command "$@"
    ;;
  run)
    shift
    firebreak_run_command "$@"
    ;;
  internal)
    shift
    internal_command=${1:-}
    case "$internal_command" in
      validate)
        shift
        exec @VALIDATE_BIN@ "$@"
        ;;
      task)
        shift
        exec @TASK_BIN@ "$@"
        ;;
      loop)
        shift
        exec @LOOP_BIN@ "$@"
        ;;
      ""|--help|-h|help)
        cat <<'EOF'
usage:
  firebreak internal validate run SUITE [--state-dir PATH]
  firebreak internal task <subcommand> ...
  firebreak internal loop run ...
EOF
        ;;
      *)
        echo "unknown firebreak internal subcommand: $internal_command" >&2
        exit 1
        ;;
    esac
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak subcommand: $command" >&2
    exit 1
    ;;
esac
