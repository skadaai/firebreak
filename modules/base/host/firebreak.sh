set -eu

command=${1:-}

@FIREBREAK_PROJECT_CONFIG_LIB@
@FIREBREAK_INIT_FUNCTIONS@
@FIREBREAK_DOCTOR_FUNCTIONS@

usage() {
  cat <<'EOF'
Skada Firebreak

usage:
  firebreak init [--force] [--stdout] [--interactive] [--non-interactive]
  firebreak doctor [--verbose] [--json]
  firebreak internal <subcommand> ...

Available commands:
  init        Interactively write Firebreak project defaults
  doctor      Explain resolved config and launch readiness
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
