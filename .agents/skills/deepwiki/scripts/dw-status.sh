#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./dw-common.sh
. "$script_dir/dw-common.sh"

usage() {
  echo 'Usage: dw-status.sh owner/repo [--warm]' >&2
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

REPO=""
DO_WARM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --warm)
      DO_WARM=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown flag: $1" >&2
      usage
      exit 1
      ;;
    *)
      REPO="$1"
      shift
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo 'Error: owner/repo is required.' >&2
  usage
  exit 1
fi

if [[ "$DO_WARM" == true ]]; then
  echo "Warming $REPO..." >&2
  run_deepwiki_cli warm "$REPO" >&2
fi

tmp_json="$(mktemp)"
cleanup() { rm -f "$tmp_json"; }
trap cleanup EXIT

run_deepwiki_json_with_retry "$tmp_json" status "$REPO"
cat "$tmp_json"

if ! jq -e '.indexed == true or .status == "completed" or .status == "indexed"' "$tmp_json" > /dev/null 2>&1; then
  exit 1
fi
