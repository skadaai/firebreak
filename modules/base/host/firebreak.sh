set -eu

firebreak_libexec_dir=${FIREBREAK_LIBEXEC_DIR:-}
if [ -z "$firebreak_libexec_dir" ]; then
  firebreak_libexec_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fi

command=${1:-}

. "$firebreak_libexec_dir/firebreak-project-config.sh"
. "$firebreak_libexec_dir/firebreak-init.sh"
. "$firebreak_libexec_dir/firebreak-doctor.sh"

firebreak_require_flake_ref() {
  if [ -z "${FIREBREAK_FLAKE_REF:-}" ]; then
    echo "FIREBREAK_FLAKE_REF is required for commands that launch Firebreak workloads" >&2
    exit 1
  fi
}

firebreak_exec_package() {
  package_name=$1
  shift

  firebreak_require_flake_ref
  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ] && [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    exec nix --accept-flake-config --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" \
      run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
  fi

  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ]; then
    exec nix --accept-flake-config run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
  fi

  if [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    exec nix --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" \
      run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
  fi

  exec nix run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
}

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

  case "$requested_vm_mode" in
    ""|run|shell)
      ;;
    *)
      echo "unsupported Firebreak VM mode: $requested_vm_mode" >&2
      run_usage 1
      ;;
  esac

  case "$vm_name" in
    codex)
      if [ -n "$requested_vm_mode" ]; then
        FIREBREAK_VM_MODE="$requested_vm_mode" firebreak_exec_package "firebreak-codex" "$@"
      else
        firebreak_exec_package "firebreak-codex" "$@"
      fi
      ;;
    claude-code)
      if [ -n "$requested_vm_mode" ]; then
        FIREBREAK_VM_MODE="$requested_vm_mode" firebreak_exec_package "firebreak-claude-code" "$@"
      else
        firebreak_exec_package "firebreak-claude-code" "$@"
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
        firebreak_exec_package "firebreak-internal-validate" "$@"
        ;;
      task)
        shift
        firebreak_exec_package "firebreak-internal-task" "$@"
        ;;
      loop)
        shift
        firebreak_exec_package "firebreak-internal-loop" "$@"
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
