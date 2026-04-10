set -eu

firebreak_libexec_dir=${FIREBREAK_LIBEXEC_DIR:-}
if [ -z "$firebreak_libexec_dir" ]; then
  firebreak_libexec_dir=$(
    CDPATH='' cd -- "$(dirname -- "$0")" && pwd
  )
fi

command=${1:-}

. "$firebreak_libexec_dir/firebreak-project-config.sh"
. "$firebreak_libexec_dir/firebreak-environment.sh"
. "$firebreak_libexec_dir/firebreak-init.sh"
. "$firebreak_libexec_dir/firebreak-doctor.sh"

firebreak_workload_registry=${FIREBREAK_WORKLOAD_REGISTRY:-}

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

firebreak_maybe_print_flake_config_hint() {
  stderr_log=$1

  if grep -F -q "Pass '--accept-flake-config' to trust it" "$stderr_log" 2>/dev/null \
    || grep -F -q "untrusted flake configuration setting" "$stderr_log" 2>/dev/null; then
    cat >&2 <<'EOF'
firebreak: Nix refused this flake's configuration.
Rerun with:
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' run ...

If you are launching Firebreak from another Firebreak command, export:
  FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=1
EOF
  fi
}

firebreak_run_nix() {
  stderr_log=$(mktemp "${TMPDIR:-/tmp}/firebreak-nix-stderr.XXXXXX")
  stderr_fifo=$(mktemp -u "${TMPDIR:-/tmp}/firebreak-nix-stderr-fifo.XXXXXX")
  mkfifo "$stderr_fifo"
  tee "$stderr_log" <"$stderr_fifo" >&2 &
  tee_pid=$!
  if "$@" 2>"$stderr_fifo"; then
    status=0
  else
    status=$?
  fi
  rm -f "$stderr_fifo"
  wait "$tee_pid" 2>/dev/null || true
  if [ "$status" -eq 0 ]; then
    rm -f "$stderr_log"
    return 0
  fi
  firebreak_maybe_print_flake_config_hint "$stderr_log"
  rm -f "$stderr_log"
  exit "$status"
}

firebreak_exec_package() {
  package_name=$1
  shift

  firebreak_require_flake_ref
  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ] && [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    firebreak_run_nix nix --accept-flake-config --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" \
      run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
    exit 0
  fi

  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ]; then
    firebreak_run_nix nix --accept-flake-config run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
    exit 0
  fi

  if [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    firebreak_run_nix nix --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" \
      run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
    exit 0
  fi

  firebreak_run_nix nix run "$FIREBREAK_FLAKE_REF#$package_name" -- "$@"
  exit 0
}

firebreak_require_workload_registry() {
  if [ -z "$firebreak_workload_registry" ] || ! [ -r "$firebreak_workload_registry" ]; then
    echo "FIREBREAK_WORKLOAD_REGISTRY is required for public Firebreak VM commands" >&2
    exit 1
  fi
}

firebreak_each_workload() {
  firebreak_require_workload_registry

  while IFS="$(printf '\t')" read -r workload_name workload_description workload_launcher || [ -n "${workload_name:-}" ]; do
    [ -n "${workload_name:-}" ] || continue
    printf '%s\t%s\t%s\n' "$workload_name" "$workload_description" "$workload_launcher"
  done <"$firebreak_workload_registry"
}

firebreak_find_workload() {
  requested_workload=$1

  while IFS="$(printf '\t')" read -r workload_name workload_description workload_launcher || [ -n "${workload_name:-}" ]; do
    [ -n "${workload_name:-}" ] || continue
    if [ "$workload_name" = "$requested_workload" ]; then
      printf '%s\t%s\t%s\n' "$workload_name" "$workload_description" "$workload_launcher"
      return 0
    fi
  done <"$firebreak_workload_registry"

  return 1
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
    printf '%s\n' '['
    first_entry=1
    while IFS="$(printf '\t')" read -r workload_name workload_description workload_launcher; do
      [ -n "$workload_name" ] || continue
      if [ "$first_entry" = "1" ]; then
        first_entry=0
      else
        printf '%s\n' ','
      fi
      python3 - "$workload_name" "$workload_description" <<'PY'
import json
import sys

name = sys.argv[1]
description = sys.argv[2]
print(json.dumps({"name": name, "description": description}, indent=2), end="")
PY
    done <<EOF
$(firebreak_each_workload)
EOF
    printf '\n%s\n' ']'
    return 0
  fi

  printf '%s\n\n' "Available Firebreak VMs"
  while IFS="$(printf '\t')" read -r workload_name workload_description workload_launcher; do
    [ -n "$workload_name" ] || continue
    printf '  %-12s %s\n' "$workload_name" "$workload_description"
  done <<EOF
$(firebreak_each_workload)
EOF
  cat <<'EOF'

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

  dispatch_run_workload() {
    workload_launcher=$1
    shift

    if [ -n "$requested_launch_mode" ] && { [ -n "$requested_worker_mode" ] || [ -n "$requested_worker_modes" ]; }; then
      FIREBREAK_LAUNCH_MODE="$requested_launch_mode" \
      FIREBREAK_WORKER_MODE="$requested_worker_mode" \
      FIREBREAK_WORKER_MODES="$requested_worker_modes" \
      exec "$workload_launcher" "$@"
      return
    fi

    if [ -n "$requested_launch_mode" ]; then
      FIREBREAK_LAUNCH_MODE="$requested_launch_mode" \
      exec "$workload_launcher" "$@"
      return
    fi

    if [ -n "$requested_worker_mode" ] || [ -n "$requested_worker_modes" ]; then
      FIREBREAK_WORKER_MODE="$requested_worker_mode" \
      FIREBREAK_WORKER_MODES="$requested_worker_modes" \
      exec "$workload_launcher" "$@"
      return
    fi

    exec "$workload_launcher" "$@"
  }

  workload_entry=$(firebreak_find_workload "$vm_name" || true)
  if [ -z "$workload_entry" ]; then
    echo "unknown Firebreak VM: $vm_name" >&2
    echo "run 'firebreak vms' to list available VMs" >&2
    exit 1
  fi

  IFS="$(printf '\t')" read -r _resolved_workload_name _resolved_workload_description resolved_workload_launcher <<EOF
$workload_entry
EOF

  if ! [ -x "$resolved_workload_launcher" ]; then
    echo "configured Firebreak workload launcher is not executable: $resolved_workload_launcher" >&2
    exit 1
  fi

  dispatch_run_workload "$resolved_workload_launcher" "$@"
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

Available commands:
  init        Interactively write Firebreak project defaults
  doctor      Explain resolved config and launch readiness
  environment Resolve the additive Firebreak environment overlay
  vms         List the public Firebreak VM workloads
  run         Launch a public Firebreak VM workload
  worker      Manage host-brokered Firebreak workers

Development workflow commands live in the separate `dev-flow` CLI.
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
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak subcommand: $command" >&2
    exit 1
    ;;
esac
