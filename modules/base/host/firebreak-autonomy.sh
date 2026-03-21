set -eu

state_dir=${FIREBREAK_SESSION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/sessions}
command=${1:-}

usage() {
  cat <<'EOF' >&2
usage:
  firebreak autonomy run \
    --session-id ID \
    --spec PATH \
    --plan TEXT \
    --validation-suite SUITE [--validation-suite SUITE ...] \
    [--write-path PATH ...] \
    [--commit-message MSG] \
    [--attempt-id ID]
EOF
  exit 1
}

json_escape() {
  value=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  value=$(printf '%s' "$value" | tr '\n' ' ')
  printf '%s' "$value"
}

extract_json_field() {
  file_path=$1
  field=$2
  sed -n "s/.*\"$field\": \"\\([^\"]*\\)\".*/\\1/p" "$file_path" | head -n 1
}

validate_token() {
  value=$1
  description=$2
  case "$value" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "$description must be a single path-safe token without whitespace: $value" >&2
      exit 1
      ;;
  esac
}

validate_suite_name() {
  suite_name=$1
  case "$suite_name" in
    ""|.|..|*/*|*[[:space:]]*)
      echo "validation suite must be a single path-safe token without whitespace: $suite_name" >&2
      exit 1
      ;;
  esac
}

validate_write_path() {
  write_path=$1
  case "$write_path" in
    ""|*[[:space:]]*)
      echo "write path must not be empty or contain whitespace: $write_path" >&2
      exit 1
      ;;
  esac
}

require_file() {
  file_path=$1
  description=$2
  if ! [ -f "$file_path" ]; then
    echo "$description is missing: $file_path" >&2
    exit 1
  fi
}

load_session() {
  session_id=$1
  session_root=$state_dir/$session_id
  metadata_path=$session_root/metadata.json
  require_file "$metadata_path" "session metadata"

  status=$(cat "$session_root/status")
  branch=$(cat "$session_root/branch")
  owner=$(cat "$session_root/owner")
  primary_checkout=$(cat "$session_root/primary-checkout")
  worktree_path=$(cat "$session_root/worktree-path")
}

emit_array() {
  list=$1
  first=1
  for item in $list; do
    if [ "$first" = "1" ]; then
      first=0
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$item")"
  done
}

emit_plan() {
  cat >"$plan_path" <<EOF
{
  "attempt_id": "$(json_escape "$attempt_id")",
  "session_id": "$(json_escape "$session_id")",
  "branch": "$(json_escape "$branch")",
  "owner": "$(json_escape "$owner")",
  "primary_checkout": "$(json_escape "$primary_checkout")",
  "spec": "$(json_escape "$spec_ref")",
  "spec_path": "$(json_escape "$spec_path")",
  "plan": "$(json_escape "$plan_text")",
  "validation_suites": [$(emit_array "$validation_suites")],
  "write_paths": [$(emit_array "$write_paths")],
  "commit_message": $(if [ -n "$commit_message" ]; then printf '"%s"' "$(json_escape "$commit_message")"; else printf 'null'; fi),
  "max_validation_suites": $max_validation_suites,
  "max_write_paths": $max_write_paths,
  "validation_retry_budget": $validation_retry_budget,
  "started_at": "$(json_escape "$started_at")"
}
EOF
}

emit_summary() {
  cat >"$summary_path" <<EOF
{
  "attempt_id": "$(json_escape "$attempt_id")",
  "session_id": "$(json_escape "$session_id")",
  "session_status": "$(json_escape "$status")",
  "branch": "$(json_escape "$branch")",
  "owner": "$(json_escape "$owner")",
  "result": "$(json_escape "$result")",
  "blocked_reason": $(if [ -n "$blocked_reason" ]; then printf '"%s"' "$(json_escape "$blocked_reason")"; else printf 'null'; fi),
  "spec_path": "$(json_escape "$spec_path")",
  "worktree_path": "$(json_escape "$worktree_path")",
  "audit_root": "$(json_escape "$attempt_root")",
  "review_path": "$(json_escape "$review_path")",
  "plan_path": "$(json_escape "$plan_path")",
  "commit_sha": $(if [ -n "$commit_sha" ]; then printf '"%s"' "$(json_escape "$commit_sha")"; else printf 'null'; fi),
  "started_at": "$(json_escape "$started_at")",
  "finished_at": "$(json_escape "$finished_at")"
}
EOF
}

block_attempt() {
  blocked_reason=$1
  result="blocked"
  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  emit_summary
  cat "$summary_path"
  exit 125
}

resolve_spec_path() {
  case "$spec_ref" in
    /*)
      spec_path=$spec_ref
      ;;
    *)
      spec_path=$worktree_path/$spec_ref
      ;;
  esac

  if ! [ -f "$spec_path" ]; then
    block_attempt "missing-spec"
  fi
}

enforce_policy() {
  if [ "$validation_suite_count" -gt "$max_validation_suites" ]; then
    printf 'validation suite count %s exceeds limit %s\n' "$validation_suite_count" "$max_validation_suites" >"$policy_path"
    block_attempt "validation-suite-limit"
  fi

  if [ "$write_path_count" -gt "$max_write_paths" ]; then
    printf 'write path count %s exceeds limit %s\n' "$write_path_count" "$max_write_paths" >"$policy_path"
    block_attempt "write-path-limit"
  fi

  : >"$policy_path"
  for write_path in $write_paths; do
    validate_write_path "$write_path"
    case "$write_path" in
      /*)
        resolved_path=$(realpath -m "$write_path")
        ;;
      *)
        resolved_path=$(realpath -m "$worktree_path/$write_path")
        ;;
    esac

    case "$resolved_path" in
      "$worktree_path"|"$worktree_path"/*)
        printf '%s\t%s\n' "$write_path" "$resolved_path" >>"$policy_path"
        ;;
      *)
        printf 'out-of-scope\t%s\t%s\n' "$write_path" "$resolved_path" >>"$policy_path"
        block_attempt "policy-write-scope"
        ;;
    esac
  done
}

run_validation_suites() {
  mkdir -p "$validation_dir"

  for suite_name in $validation_suites; do
    validate_suite_name "$suite_name"
    suite_output_path=$validation_dir/$suite_name.json
    suite_exit_path=$validation_dir/$suite_name.exit_code
    validation_attempt=0

    while :; do
      set +e
      suite_output=$(@SESSION_BIN@ validate --session-id "$session_id" "$suite_name")
      suite_status=$?
      set -e

      printf '%s\n' "$suite_output" >"$suite_output_path"
      printf '%s\n' "$suite_status" >"$suite_exit_path"
      suite_result=$(extract_json_field "$suite_output_path" result)

      case "$suite_result" in
        passed)
          break
          ;;
        failed)
          if [ "$validation_attempt" -lt "$validation_retry_budget" ]; then
            validation_attempt=$((validation_attempt + 1))
            continue
          fi
          block_attempt "validation-failed"
          ;;
        blocked)
          block_attempt "validation-blocked"
          ;;
        *)
          if [ "$suite_status" -ne 0 ]; then
            block_attempt "validation-command-failed"
          fi
          block_attempt "validation-unknown-result"
          ;;
      esac
    done
  done
}

run_review() {
  mkdir -p "$review_dir"
  diff_check_log=$review_dir/diff-check.log
  diff_stat_log=$review_dir/diff-stat.log
  conflicts_log=$review_dir/conflicts.log
  status_log=$review_dir/status.log

  git -C "$worktree_path" status --porcelain >"$status_log"
  git -C "$worktree_path" diff --stat >"$diff_stat_log"
  git -C "$worktree_path" diff --name-only --diff-filter=U >"$conflicts_log"

  set +e
  git -C "$worktree_path" diff --check >"$diff_check_log" 2>&1
  diff_check_status=$?
  set -e

  conflict_count=$(wc -l <"$conflicts_log" | tr -d ' ')
  diff_check_count=$(wc -l <"$diff_check_log" | tr -d ' ')

  review_result="passed"
  if [ "$diff_check_status" -ne 0 ] || [ "$conflict_count" -ne 0 ]; then
    review_result="failed"
  fi

  cat >"$review_path" <<EOF
{
  "session_id": "$(json_escape "$session_id")",
  "review_result": "$(json_escape "$review_result")",
  "diff_check_status": $diff_check_status,
  "diff_check_line_count": $diff_check_count,
  "conflict_count": $conflict_count,
  "status_path": "$(json_escape "$status_log")",
  "diff_stat_path": "$(json_escape "$diff_stat_log")",
  "diff_check_path": "$(json_escape "$diff_check_log")",
  "conflicts_path": "$(json_escape "$conflicts_log")"
}
EOF

  if [ "$review_result" != "passed" ]; then
    block_attempt "review-failed"
  fi
}

create_commit() {
  if [ -z "$commit_message" ]; then
    return 0
  fi

  status_log=$review_dir/status.log
  if ! [ -s "$status_log" ]; then
    block_attempt "no-changes-to-commit"
  fi

  (
    cd "$worktree_path"
    git add -A
    GIT_AUTHOR_NAME=${FIREBREAK_AUTONOMY_AUTHOR_NAME:-"Firebreak Autonomy"} \
      GIT_AUTHOR_EMAIL=${FIREBREAK_AUTONOMY_AUTHOR_EMAIL:-"firebreak@example.invalid"} \
      GIT_COMMITTER_NAME=${FIREBREAK_AUTONOMY_COMMITTER_NAME:-"Firebreak Autonomy"} \
      GIT_COMMITTER_EMAIL=${FIREBREAK_AUTONOMY_COMMITTER_EMAIL:-"firebreak@example.invalid"} \
      git commit -m "$commit_message" >/dev/null
  )
  commit_sha=$(git -C "$worktree_path" rev-parse HEAD)
}

run_attempt() {
  session_id=""
  spec_ref=""
  plan_text=""
  validation_suites=""
  write_paths=""
  commit_message=""
  attempt_id=${FIREBREAK_ATTEMPT_ID:-}

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session-id)
        session_id=$2
        shift 2
        ;;
      --spec)
        spec_ref=$2
        shift 2
        ;;
      --plan)
        plan_text=$2
        shift 2
        ;;
      --validation-suite)
        validate_suite_name "$2"
        validation_suites="$validation_suites $2"
        shift 2
        ;;
      --write-path)
        validate_write_path "$2"
        write_paths="$write_paths $2"
        shift 2
        ;;
      --commit-message)
        commit_message=$2
        shift 2
        ;;
      --attempt-id)
        attempt_id=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  if [ -z "$session_id" ] || [ -z "$spec_ref" ] || [ -z "$plan_text" ] || [ -z "$validation_suites" ]; then
    usage
  fi

  validate_token "$session_id" "session id"
  if [ -z "$attempt_id" ]; then
    attempt_id="$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  validate_token "$attempt_id" "attempt id"

  load_session "$session_id"
  if [ "$status" != "active" ]; then
    echo "cannot run autonomy loop for inactive session '$session_id' with status '$status'" >&2
    exit 1
  fi
  if ! [ -d "$worktree_path" ]; then
    echo "session worktree is missing: $worktree_path" >&2
    exit 1
  fi

  validation_suites=$(printf '%s\n' "$validation_suites" | xargs)
  write_paths=$(printf '%s\n' "$write_paths" | xargs)
  validation_suite_count=$(printf '%s\n' "$validation_suites" | wc -w | tr -d ' ')
  write_path_count=$(printf '%s\n' "$write_paths" | wc -w | tr -d ' ')
  max_validation_suites=${FIREBREAK_AUTONOMY_MAX_VALIDATION_SUITES:-8}
  max_write_paths=${FIREBREAK_AUTONOMY_MAX_WRITE_PATHS:-32}
  validation_retry_budget=${FIREBREAK_AUTONOMY_VALIDATION_RETRIES:-0}

  attempt_root=$session_root/autonomy/$attempt_id
  if [ -e "$attempt_root" ]; then
    echo "autonomy attempt already exists: $attempt_id" >&2
    exit 125
  fi
  plan_path=$attempt_root/plan.json
  policy_path=$attempt_root/policy.log
  validation_dir=$attempt_root/validation
  review_dir=$attempt_root/review
  review_path=$review_dir/review.json
  summary_path=$attempt_root/summary.json
  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  result="completed"
  blocked_reason=""
  commit_sha=""

  mkdir -p "$attempt_root"
  resolve_spec_path
  emit_plan
  enforce_policy
  run_validation_suites
  run_review
  create_commit

  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  emit_summary
  cat "$summary_path"
}

case "$command" in
  run)
    shift
    run_attempt "$@"
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown firebreak autonomy subcommand: $command" >&2
    usage
    ;;
esac
