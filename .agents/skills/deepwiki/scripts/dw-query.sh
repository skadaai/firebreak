#!/usr/bin/env bash
# dw-query.sh — query DeepWiki and print the answer + sources from one request.
#
# Usage:
#   dw-query.sh "question" owner/repo [owner/repo2 ...]
#               [--mode deep|fast|codemap] [--context "text"]
#               [--id query-id] [--mermaid] [--sources-only] [--json]
#
# Default output (one request, one response):
#   1. Answer prose
#   2. Sources: list of file paths DeepWiki used from that same response
#   3. Thread-ID: message_id to use with --id for follow-up queries
#
# Options:
#   --mode       deep (default) | fast | codemap
#   --context    Extra context injected into the query
#   --id         Reuse a previous query's Thread-ID for follow-up threading
#   --mermaid    Output Mermaid diagram (codemap mode only)
#   --sources-only  Print only the source file paths, one per line
#   --json       Print the raw JSON response (skips all extraction)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./dw-common.sh
. "$script_dir/dw-common.sh"

usage() {
  cat >&2 <<'EOF'
Usage: dw-query.sh "question" owner/repo [owner/repo2 ...]
                   [--mode deep|fast|codemap] [--context "text"]
                   [--id query-id] [--mermaid] [--sources-only] [--json]
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

QUESTION="$1"
shift

REPOS=()
MODE="deep"
CONTEXT=""
ID=""
MERMAID=false
SOURCES_ONLY=false
RAW_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m)
      MODE="${2:?'--mode requires a value'}"
      shift 2
      ;;
    --context|-c)
      CONTEXT="${2:?'--context requires a value'}"
      shift 2
      ;;
    --id)
      ID="${2:?'--id requires a value'}"
      shift 2
      ;;
    --mermaid)
      MERMAID=true
      shift
      ;;
    --sources-only)
      SOURCES_ONLY=true
      shift
      ;;
    --json)
      RAW_JSON=true
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
      REPOS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Error: at least one owner/repo is required." >&2
  usage
  exit 1
fi

ARGS=(query "$QUESTION")
for repo in "${REPOS[@]}"; do
  ARGS+=(-r "$repo")
done
ARGS+=(-m "$MODE")
[[ -n "$CONTEXT" ]] && ARGS+=(-c "$CONTEXT")
[[ -n "$ID" ]]      && ARGS+=(--id "$ID")
[[ "$MERMAID" == true ]] && ARGS+=(--mermaid)

TMP_JSON="$(mktemp)"
cleanup() { rm -f "$TMP_JSON"; }
trap cleanup EXIT

run_deepwiki_json_with_retry "$TMP_JSON" "${ARGS[@]}"

if [[ "$RAW_JSON" == true ]]; then
  cat "$TMP_JSON"
  exit 0
fi

if [[ "$SOURCES_ONLY" == true ]]; then
  jq -r '.. | objects | select(.type? == "file_contents") | .data[1]? // empty' "$TMP_JSON" \
    | awk '!seen[$0]++'
  exit 0
fi

# Answer prose
jq -rj '.. | objects | select(.type? == "chunk" or .type? == "summary_chunk") | .data? // empty' "$TMP_JSON"

echo

# Source files from the same response
SOURCES="$(jq -r '.. | objects | select(.type? == "file_contents") | .data[1]? // empty' "$TMP_JSON" \
  | awk '!seen[$0]++')"
if [[ -n "$SOURCES" ]]; then
  echo "Sources:"
  echo "$SOURCES" | sed 's/^/- /'
  echo
fi

# Thread ID for follow-up queries
THREAD_ID="$(jq -r '.queries[0].message_id? // empty' "$TMP_JSON")"
if [[ -n "$THREAD_ID" ]]; then
  echo "Thread-ID: $THREAD_ID"
fi
