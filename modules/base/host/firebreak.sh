set -eu

firebreak_libexec_dir=${FIREBREAK_LIBEXEC_DIR:-}
if [ -z "$firebreak_libexec_dir" ]; then
  firebreak_libexec_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fi

command=${1:-}

. "$firebreak_libexec_dir/firebreak-project-config.sh"
. "$firebreak_libexec_dir/firebreak-environment.sh"
. "$firebreak_libexec_dir/firebreak-init.sh"
. "$firebreak_libexec_dir/firebreak-doctor.sh"

firebreak_exec_libexec() {
  script_name=$1
  shift
  exec bash "$firebreak_libexec_dir/$script_name" "$@"
}

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
  firebreak run <vm> [--shell] [--launch-mode <run|shell>] [--worker-mode <vm|local|name=vm|name=local>] [-- <vm args...>]
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
  firebreak run codex --launch-mode shell
  firebreak run codex --worker-mode local
  firebreak run codex --worker-mode codex=vm --worker-mode claude=local
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

  requested_launch_mode=${FIREBREAK_LAUNCH_MODE:-}
  requested_worker_mode=${FIREBREAK_WORKER_MODE:-}
  requested_worker_modes=${FIREBREAK_WORKER_MODES:-}

  append_worker_mode_override() {
    worker_mode_entry=$1
    if [ -n "$requested_worker_modes" ]; then
      requested_worker_modes="${requested_worker_modes}
$worker_mode_entry"
    else
      requested_worker_modes=$worker_mode_entry
    fi
  }

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --shell)
        requested_launch_mode=shell
        shift
        ;;
      --launch-mode)
        [ "$#" -ge 2 ] || {
          echo "missing value for --launch-mode" >&2
          run_usage 1
        }
        requested_launch_mode=$2
        shift 2
        ;;
      --launch-mode=*)
        requested_launch_mode=${1#*=}
        shift
        ;;
      --worker-mode)
        [ "$#" -ge 2 ] || {
          echo "missing value for --worker-mode" >&2
          run_usage 1
        }
        case "$2" in
          *=*)
            append_worker_mode_override "$2"
            ;;
          *)
            requested_worker_mode=$2
            ;;
        esac
        shift 2
        ;;
      --worker-mode=*)
        worker_mode_value=${1#*=}
        case "$worker_mode_value" in
          *=*)
            append_worker_mode_override "$worker_mode_value"
            ;;
          *)
            requested_worker_mode=$worker_mode_value
            ;;
        esac
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

  case "$requested_launch_mode" in
    ""|run|shell)
      ;;
    *)
      echo "unsupported Firebreak launch mode: $requested_launch_mode" >&2
      run_usage 1
      ;;
  esac

  normalize_worker_mode() {
    case "$1" in
      worker)
        printf '%s\n' "vm"
        ;;
      *)
        printf '%s\n' "$1"
        ;;
    esac
  }

  requested_worker_mode=$(normalize_worker_mode "$requested_worker_mode")

  case "$requested_worker_mode" in
    ""|vm|local)
      ;;
    *)
      echo "unsupported FIREBREAK_WORKER_MODE: $requested_worker_mode" >&2
      echo "supported values: vm, local" >&2
      run_usage 1
      ;;
  esac

  if [ -n "$requested_worker_modes" ]; then
    normalized_worker_modes=""
    while IFS= read -r worker_mode_entry || [ -n "$worker_mode_entry" ]; do
      worker_mode_entry=${worker_mode_entry#"${worker_mode_entry%%[![:space:]]*}"}
      worker_mode_entry=${worker_mode_entry%"${worker_mode_entry##*[![:space:]]}"}
      [ -n "$worker_mode_entry" ] || continue
      case "$worker_mode_entry" in
        *=*)
          worker_name=${worker_mode_entry%%=*}
          worker_mode_value=$(normalize_worker_mode "${worker_mode_entry#*=}")
          case "$worker_mode_value" in
            vm|local)
              ;;
            *)
              echo "unsupported FIREBREAK_WORKER_MODE override: $worker_mode_entry" >&2
              echo "supported override values: name=vm, name=local" >&2
              exit 1
              ;;
          esac
          case "$worker_name" in
            ""|*[!A-Za-z0-9._-]*)
              echo "unsupported FIREBREAK_WORKER_MODE override target: $worker_name" >&2
              exit 1
              ;;
          esac
          if [ -n "$normalized_worker_modes" ]; then
            normalized_worker_modes="${normalized_worker_modes}
${worker_name}=${worker_mode_value}"
          else
            normalized_worker_modes="${worker_name}=${worker_mode_value}"
          fi
          ;;
        *)
          echo "unsupported FIREBREAK_WORKER_MODE override: $worker_mode_entry" >&2
          echo "supported override values: name=vm, name=local" >&2
          exit 1
          ;;
      esac
    done <<EOF
$requested_worker_modes
EOF
    requested_worker_modes=$normalized_worker_modes
  fi

  dispatch_run_package() {
    package_name=$1
    shift

    if [ -n "$requested_launch_mode" ] && { [ -n "$requested_worker_mode" ] || [ -n "$requested_worker_modes" ]; }; then
      FIREBREAK_LAUNCH_MODE="$requested_launch_mode" \
      FIREBREAK_WORKER_MODE="$requested_worker_mode" \
      FIREBREAK_WORKER_MODES="$requested_worker_modes" \
      firebreak_exec_package "$package_name" "$@"
      return
    fi

    if [ -n "$requested_launch_mode" ]; then
      FIREBREAK_LAUNCH_MODE="$requested_launch_mode" \
      firebreak_exec_package "$package_name" "$@"
      return
    fi

    if [ -n "$requested_worker_mode" ] || [ -n "$requested_worker_modes" ]; then
      FIREBREAK_WORKER_MODE="$requested_worker_mode" \
      FIREBREAK_WORKER_MODES="$requested_worker_modes" \
      firebreak_exec_package "$package_name" "$@"
      return
    fi

    firebreak_exec_package "$package_name" "$@"
  }

  case "$vm_name" in
    codex)
      dispatch_run_package "firebreak-codex" "$@"
      ;;
    claude-code)
      dispatch_run_package "firebreak-claude-code" "$@"
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
  firebreak environment resolve [--json]
  firebreak vms [--json]
  firebreak run <vm> [--shell] [--launch-mode <run|shell>] [--worker-mode <vm|local|name=vm|name=local>] [-- <vm args...>]
  firebreak worker <subcommand> ...
  firebreak internal <subcommand> ...

Available commands:
  init        Interactively write Firebreak project defaults
  doctor      Explain resolved config and launch readiness
  environment Resolve the additive Firebreak environment overlay
  vms         List the public Firebreak VM workloads
  run         Launch a public Firebreak VM workload
  worker      Manage host-brokered Firebreak workers
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
  environment)
    shift
    environment_subcommand=${1:-}
    case "$environment_subcommand" in
      resolve)
        shift
        firebreak_environment_resolve_command "$@"
        ;;
      ""|--help|-h|help)
        cat <<'EOF'
usage:
  firebreak environment resolve [--json]
EOF
        ;;
      *)
        echo "unknown firebreak environment subcommand: $environment_subcommand" >&2
        exit 1
        ;;
    esac
    ;;
  vms)
    shift
    firebreak_vms_command "$@"
    ;;
  run)
    shift
    firebreak_run_command "$@"
    ;;
  worker)
    shift
    firebreak_exec_libexec "firebreak-worker.sh" "$@"
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
