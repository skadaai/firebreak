#!/usr/bin/env bash
# dw-query — query DeepWiki and print the answer to stdout.
#
# Usage:
#   dw-query.sh "question" owner/repo [owner/repo2 ...] [--mode deep|fast|codemap]
#               [--context "extra context"] [--id <prev-query-id>] [--mermaid]
#
# Defaults: mode=deep.
#
# Examples:
#   ./scripts/dw-query.sh "How does routing work?" vitejs/vite
#   ./scripts/dw-query.sh "Compare routing" expressjs/express koajs/koa --mode fast
#   ./scripts/dw-query.sh "How does HMR work?" vitejs/vite --context "I am using React 19"
#   ./scripts/dw-query.sh "Tell me more" vitejs/vite --id abc123
#   ./scripts/dw-query.sh "Show the build pipeline" vitejs/vite --mode codemap --mermaid

set -euo pipefail

QUESTION=""
REPOS=()
MODE="deep"
CONTEXT=""
ID=""
MERMAID=false

if [[ $# -eq 0 ]]; then
  echo "Usage: dw-query.sh \"question\" owner/repo [owner/repo2 ...] [--mode MODE] [--context TEXT] [--id ID] [--mermaid]" >&2
  exit 1
fi

QUESTION="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m)    MODE="$2";    shift 2 ;;
    --context|-c) CONTEXT="$2"; shift 2 ;;
    --id)         ID="$2";      shift 2 ;;
    --mermaid)    MERMAID=true; shift ;;
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
[[ "$MERMAID" == true ]] && ARGS+=("--mermaid")

bunx @qwadratic/deepwiki-cli "${ARGS[@]}" \
  | jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty'
