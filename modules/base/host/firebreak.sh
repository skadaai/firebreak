set -eu

command=${1:-}

usage() {
  cat <<'EOF'
Skada Firebreak

usage:
  firebreak internal <subcommand> ...

Available commands:
  internal    Internal plumbing for agents and automation

Human-facing commands remain reserved until they have clear user value and intuitive UX.
EOF
}

case "$command" in
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
