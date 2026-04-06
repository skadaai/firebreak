#!/usr/bin/env bash

DEEPWIKI_PACKAGE="@qwadratic/deepwiki-cli"
deepwiki_retry_count="${DEEPWIKI_RETRY_COUNT:-3}"
deepwiki_progress_mode="${DEEPWIKI_PROGRESS_MODE:-auto}"

run_deepwiki_cli() {
  local status=0

  if command -v bunx >/dev/null 2>&1; then
    if bunx --silent -p "$DEEPWIKI_PACKAGE" deepwiki "$@"; then
      return 0
    else
      status=$?
    fi
  fi

  if command -v npx >/dev/null 2>&1; then
    if npx --yes -p "$DEEPWIKI_PACKAGE" deepwiki "$@"; then
      return 0
    else
      status=$?
    fi
  fi

  if command -v pnpx >/dev/null 2>&1; then
    if pnpx "$DEEPWIKI_PACKAGE" deepwiki "$@"; then
      return 0
    else
      status=$?
    fi
  fi

  if [ "$status" -eq 0 ]; then
    echo '{"error":"No supported DeepWiki launcher found; tried bunx, npx, and pnpx"}' >&2
    return 127
  fi

  return "$status"
}

is_transient_deepwiki_error() {
  local response_path="$1"
  jq -e '
    (.error? // "") as $error
    | ($error | test("HTTP 50[234]|Gateway Time-out|Bad Gateway|Service Unavailable"; "i"))
  ' "$response_path" >/dev/null 2>&1
}

deepwiki_first_ndjson_error() {
  local response_path="$1"
  jq -rse '
    [
      .[]
      | if has("queries") then .queries[0].error? else .error? end
      | select(type == "string" and length > 0)
    ]
    | first // empty
  ' "$response_path"
}

deepwiki_ndjson_has_no_error() {
  local response_path="$1"
  jq -e -s '
    all(
      .[];
      if has("queries") then .queries[0].error? == null else .error? == null end
    )
  ' "$response_path" >/dev/null 2>&1
}

is_transient_deepwiki_ndjson_error() {
  local response_path="$1"
  local error_message

  error_message="$(deepwiki_first_ndjson_error "$response_path")"
  [ -n "$error_message" ] || return 1

  printf '%s\n' "$error_message" \
    | grep -Eiq 'HTTP 50[234]|Gateway Time-out|Bad Gateway|Service Unavailable'
}

deepwiki_progress_enabled() {
  case "$deepwiki_progress_mode" in
    always|plain)
      return 0
      ;;
    quiet|never)
      return 1
      ;;
    auto|"")
      [ -t 2 ]
      ;;
    *)
      [ -t 2 ]
      ;;
  esac
}

run_deepwiki_json_with_retry() {
  local output_path="$1"
  shift

  local attempt=1
  local delay=2
  local status

  while :; do
    if run_deepwiki_cli "$@" >"$output_path"; then
      status=0
    else
      status=$?
    fi

    if [ "$status" -eq 0 ] && jq -e '.error? == null' "$output_path" >/dev/null 2>&1; then
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

    if is_transient_deepwiki_error "$output_path"; then
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
