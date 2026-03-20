#!/usr/bin/env bash
set -eu

subcommand=${1:-}
flake_ref=${2:-}

if [ -z "$subcommand" ] || [ -z "$flake_ref" ]; then
  echo "usage: run-flake.sh <nix-subcommand> <flake-ref> [args...]" >&2
  exit 1
fi

shift 2

repo_root=$(git rev-parse --show-toplevel)
scratch_root=${FIREBREAK_RUN_FLAKE_TMPDIR:-${XDG_CACHE_HOME:-/cache}/firebreak/run-flake}
mkdir -p "$scratch_root"
tmp_dir=$(mktemp -d "$scratch_root/export.XXXXXX")
src_dir=$tmp_dir/source

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$src_dir"

(
  cd "$repo_root"
  git ls-files --cached --modified --others --exclude-standard -z |
    while IFS= read -r -d '' path; do
      case "$path" in
        .codex|.codex/*|.claude|.claude/*|.direnv|.direnv/*|.agent-sandbox.env|result|result/*|*.img|*.socket)
          continue
          ;;
      esac
      cp -a --parents "$path" "$src_dir"
    done
)

case "$flake_ref" in
  .#*)
    flake_ref="path:$src_dir#${flake_ref#.\#}"
    ;;
  .)
    flake_ref="path:$src_dir"
    ;;
esac

exec nix --accept-flake-config --extra-experimental-features 'nix-command flakes' "$subcommand" "$flake_ref" "$@"
