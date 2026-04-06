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
#   Progress, when enabled, is written to stderr only.
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

progress_phase=""
progress_source_count=0
progress_reference_count=0
progress_started_at="$(date +%s)"
progress_last_heartbeat_secs=""
stream_cli_pid=""
stream_fifo_path=""

usage() {
  cat >&2 <<'EOF'
Usage: dw-query.sh "question" owner/repo [owner/repo2 ...]
                   [--mode deep|fast|codemap] [--context "text"]
                   [--id query-id] [--mermaid] [--sources-only] [--json]
EOF
}

progress_log() {
  if deepwiki_progress_enabled; then
    printf '> %s\n' "$1" >&2
  fi
}

is_progress_chunk_text() {
  local chunk_text="$1"
  printf '%s' "$chunk_text" | jq -Rn '
    input
    | test("^[[:space:]]*(> [^\\n]+[[:space:]]*)+$")
  ' >/dev/null 2>&1
}

is_blank_chunk_text() {
  local chunk_text="$1"
  printf '%s' "$chunk_text" | jq -Rn '
    input
    | test("^[[:space:]]*$")
  ' >/dev/null 2>&1
}

set_progress_phase() {
  local phase="$1"
  local message="$2"

  if [ "$progress_phase" != "$phase" ]; then
    progress_phase="$phase"
    progress_log "$message"
  fi
}

start_progress_heartbeat() {
  progress_last_heartbeat_secs=""
}

stop_progress_heartbeat() {
  progress_last_heartbeat_secs=""
}

cleanup_stream_state() {
  if [ -n "$stream_cli_pid" ]; then
    kill "$stream_cli_pid" 2>/dev/null || true
    wait "$stream_cli_pid" 2>/dev/null || true
    stream_cli_pid=""
  fi

  if [ -n "$stream_fifo_path" ] && [ -p "$stream_fifo_path" ]; then
    rm -f "$stream_fifo_path"
    stream_fifo_path=""
  fi
}

emit_progress_heartbeat() {
  local elapsed

  if ! deepwiki_progress_enabled; then
    return
  fi

  elapsed="$(( $(date +%s) - progress_started_at ))"
  if [ "$elapsed" != "$progress_last_heartbeat_secs" ]; then
    progress_last_heartbeat_secs="$elapsed"
    progress_log "Still working... ${elapsed}s elapsed"
  fi
}

handle_stream_event() {
  local line="$1"
  local event_type=""
  local all_done=""
  local source_count=""
  local chunk_text=""

  if ! deepwiki_progress_enabled; then
    return
  fi

  event_type="$(printf '%s\n' "$line" | jq -r 'if has("queries") then "envelope" else (.type // empty) end' 2>/dev/null || true)"

  case "$event_type" in
    envelope)
      if printf '%s\n' "$line" | jq -e 'any(.queries[0].response[]?; .type == "file_contents")' >/dev/null 2>&1; then
        source_count="$(printf '%s\n' "$line" | jq -r '[.queries[0].response[]? | select(.type == "file_contents")] | length')"
        progress_source_count=$((progress_source_count + source_count))
        set_progress_phase "searching" "Searching codebase..."
      fi
      ;;
    loading_indexes)
      all_done="$(printf '%s\n' "$line" | jq -r '.data.all_done // empty' 2>/dev/null || true)"
      if [ "$all_done" = "true" ]; then
        progress_log "Indexes ready."
      else
        set_progress_phase "indexing" "Loading repo indexes..."
      fi
      ;;
    file_contents)
      progress_source_count=$((progress_source_count + 1))
      set_progress_phase "searching" "Searching codebase..."
      if [ $((progress_source_count % 25)) -eq 0 ]; then
        progress_log "Searching codebase... (${progress_source_count} source files inspected)"
      fi
      ;;
    chunk|summary_chunk)
      chunk_text="$(printf '%s\n' "$line" | jq -r '.data // ""' 2>/dev/null || true)"
      if is_blank_chunk_text "$chunk_text"; then
        return 0
      fi
      if is_progress_chunk_text "$chunk_text"; then
        chunk_text="$(printf '%s' "$chunk_text" | sed -e 's/^[[:space:]]*>[[:space:]]*//' -e 's/[[:space:]]*$//')"
        case "$chunk_text" in
          "Searching codebase..."*)
            set_progress_phase "searching" "Searching codebase..."
            ;;
          *)
            progress_log "$chunk_text"
            ;;
        esac
        return 0
      fi
      if [ "$progress_phase" != "finalizing" ] && [ "$progress_phase" != "done" ]; then
        set_progress_phase "answering" "Synthesizing answer..."
      fi
      ;;
    reference)
      progress_reference_count=$((progress_reference_count + 1))
      if [ "$progress_phase" != "answering" ]; then
        set_progress_phase "answering" "Grounding answer..."
      elif [ $((progress_reference_count % 10)) -eq 0 ]; then
        progress_log "Grounding answer... (${progress_reference_count} references)"
      fi
      ;;
    summary_done)
      set_progress_phase "finalizing" "Summary complete. Finalizing answer..."
      ;;
    done)
      set_progress_phase "done" "Response complete."
      ;;
  esac
}

extract_answer_text() {
  local stream_path="$1"
  jq -rjse '
    def events:
      .[]
      | if has("queries") then .queries[0].response[]? else . end;
    def blank_chunk:
      ((.data // "") | test("^[[:space:]]*$"));
    def progress_chunk:
      .type == "chunk"
      and ((.data // "") | test("^[[:space:]]*(> [^\\n]+[[:space:]]*)+$"));
    ([events | select(.type == "chunk" and (progress_chunk | not) and (blank_chunk | not)) | .data // empty] | join("")) as $chunks
    | if $chunks != "" then
        $chunks
      else
        [events | select(.type == "summary_chunk" and (blank_chunk | not)) | .data // empty] | join("")
      end
  ' "$stream_path"
}

extract_source_paths() {
  local stream_path="$1"
  jq -rse '
    def events:
      .[]
      | if has("queries") then .queries[0].response[]? else . end;
    ([events | select(.type == "file_contents") | .data[1]? | select(type == "string" and length > 0)] | unique) as $file_paths
    | if ($file_paths | length) > 0 then
        $file_paths[]
      else
        [
          events
          | select(.type == "reference")
          | .data.file_path?
          | sub("^Repo [^:]+: "; "")
          | select(type == "string" and length > 0)
        ]
        | unique[]
      end
  ' "$stream_path"
}

extract_thread_id() {
  local stream_path="$1"
  jq -rse '
    .[]
    | select(has("queries"))
    | .queries[0].message_id? // empty
  ' "$stream_path"
}

run_stream_query_with_retry() {
  local output_path="$1"
  shift

  local attempt=1
  local delay=2
  local status
  local stream_args=("$@" --stream)
  local line
  local read_status
  local stream_fd=3

  while :; do
    : >"$output_path"
    progress_phase=""
    progress_source_count=0
    progress_reference_count=0
    progress_started_at="$(date +%s)"
    start_progress_heartbeat
    stream_fifo_path="$(mktemp -u)"
    mkfifo "$stream_fifo_path"

    run_deepwiki_cli "${stream_args[@]}" >"$stream_fifo_path" &
    stream_cli_pid=$!
    exec 3<"$stream_fifo_path"

    while :; do
      if IFS= read -r -t 15 -u "$stream_fd" line; then
        printf '%s\n' "$line" >>"$output_path"
        handle_stream_event "$line"
        continue
      fi

      read_status=$?
      if [ "$read_status" -gt 128 ]; then
        emit_progress_heartbeat
        continue
      fi

      break
    done

    if wait "$stream_cli_pid"; then
      status=0
    else
      status=$?
    fi
    exec 3<&-
    stream_cli_pid=""
    rm -f "$stream_fifo_path"
    stream_fifo_path=""

    stop_progress_heartbeat

    if [ "$status" -eq 0 ] && deepwiki_ndjson_has_no_error "$output_path"; then
      return 0
    fi

    if [ "$attempt" -ge "$deepwiki_retry_count" ]; then
      if [ -s "$output_path" ]; then
        cat "$output_path" >&2
      else
        echo '{"error":"DeepWiki request failed"}' >&2
      fi
      return 1
    fi

    if is_transient_deepwiki_ndjson_error "$output_path"; then
      progress_log "DeepWiki service unavailable. Retrying..."
      sleep "$delay"
      attempt=$((attempt + 1))
      delay=$((delay * 2))
      continue
    fi

    if [ -s "$output_path" ]; then
      cat "$output_path" >&2
    fi
    return 1
  done
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
TMP_STREAM="$(mktemp)"
cleanup() {
  stop_progress_heartbeat
  cleanup_stream_state
  rm -f "$TMP_JSON" "$TMP_STREAM"
}
trap cleanup EXIT

if [[ "$RAW_JSON" == true ]]; then
  run_deepwiki_json_with_retry "$TMP_JSON" "${ARGS[@]}"
  cat "$TMP_JSON"
  exit 0
fi

run_stream_query_with_retry "$TMP_STREAM" "${ARGS[@]}"

if [[ "$SOURCES_ONLY" == true ]]; then
  extract_source_paths "$TMP_STREAM"
  exit 0
fi

# Answer prose
extract_answer_text "$TMP_STREAM"

echo

# Source files from the same response
SOURCES="$(extract_source_paths "$TMP_STREAM")"
if [[ -n "$SOURCES" ]]; then
  echo "Sources:"
  echo "$SOURCES" | sed 's/^/- /'
  echo
fi

# Thread ID for follow-up queries
THREAD_ID="$(extract_thread_id "$TMP_STREAM")"
if [[ -n "$THREAD_ID" ]]; then
  echo "Thread-ID: $THREAD_ID"
fi
