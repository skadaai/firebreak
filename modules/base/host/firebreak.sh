set -eu

command=${1:-}

usage() {
  cat <<'EOF'
Skada Firebreak

usage:
  firebreak validate SUITE [--state-dir PATH]
  firebreak session <subcommand> ...

Named validation suites:
  local-smoke
  codex-smoke
  codex-version
  claude-code-smoke
  cloud-smoke

Session subcommands:
  create
  show
  validate
  close
EOF
}

case "$command" in
  validate)
    shift
    exec @VALIDATE_BIN@ "$@"
    ;;
  session)
    shift
    exec @SESSION_BIN@ "$@"
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak subcommand: $command" >&2
    usage >&2
    exit 1
    ;;
esac
