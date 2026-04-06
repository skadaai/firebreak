#!/usr/bin/env bash
set -euo pipefail

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
  bunx @qwadratic/deepwiki-cli warm "$REPO" >&2
fi

RESULT="$(bunx @qwadratic/deepwiki-cli status "$REPO")"
echo "$RESULT"

if echo "$RESULT" | jq -e '.indexed == false or .status == "not_indexed"' > /dev/null 2>&1; then
  exit 1
fi
