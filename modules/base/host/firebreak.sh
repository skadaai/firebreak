set -eu

command=${1:-}

usage() {
  cat <<'EOF'
Skada Firebreak

usage:
  firebreak validate SUITE [--state-dir PATH]

Named validation suites:
  local-smoke
  codex-smoke
  claude-code-smoke
  cloud-smoke
EOF
}

case "$command" in
  validate)
    shift
    exec @VALIDATE_BIN@ "$@"
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
