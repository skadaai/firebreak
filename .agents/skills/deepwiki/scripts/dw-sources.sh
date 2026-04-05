#!/usr/bin/env bash
# dw-sources — same as dw-query but prints the source file paths DeepWiki
#              used as context, one per line, instead of the answer prose.
#
# Useful for discovering which files to read directly after a high-level answer.
#
# Usage:
#   dw-sources.sh "question" owner/repo [owner/repo2 ...] [--mode deep|fast|codemap]
#                 [--context TEXT] [--id ID]
#
# Example:
#   ./scripts/dw-sources.sh "How does the plugin lifecycle work?" vitejs/vite

set -euo pipefail

QUESTION=""
REPOS=()
MODE="deep"
CONTEXT=""
ID=""

if [[ $# -eq 0 ]]; then
  echo "Usage: dw-sources.sh \"question\" owner/repo [owner/repo2 ...] [--mode MODE] [--context TEXT] [--id ID]" >&2
  exit 1
fi

QUESTION="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m)    MODE="$2";    shift 2 ;;
    --context|-c) CONTEXT="$2"; shift 2 ;;
    --id)         ID="$2";      shift 2 ;;
    --*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      REPOS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Error: at least one owner/repo is required." >&2
  exit 1
fi

ARGS=("query" "$QUESTION")
for repo in "${REPOS[@]}"; do
  ARGS+=("-r" "$repo")
done
ARGS+=("-m" "$MODE")
[[ -n "$CONTEXT" ]] && ARGS+=("-c" "$CONTEXT")
[[ -n "$ID" ]]      && ARGS+=("--id" "$ID")

bunx @qwadratic/deepwiki-cli "${ARGS[@]}" \
  | jq -r '.. | objects | select(.type? == "file_contents") | .data[1]? // empty'
