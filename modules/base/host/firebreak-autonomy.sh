set -euf

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
    ""|.|..|*/*|*[[:space:]]*|*[\*\?\[\]]*)
      echo "validation suite must be a single path-safe token without whitespace: $suite_name" >&2
      exit 1
      ;;
  esac
}

validate_write_path() {
  write_path=$1
  case "$write_path" in
    ""|*[[:space:]]*|*[\*\?\[\]]*)
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
  worktree_shared_root=$(cat "$session_root/worktree-shared-root")
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

check_runtime_budget() {
  now_epoch=$(date -u +%s)
  elapsed_secs=$((now_epoch - started_epoch))
  remaining_runtime_secs=$((max_runtime_secs - elapsed_secs))
  if [ "$remaining_runtime_secs" -le 0 ]; then
    block_attempt "policy-runtime-limit"
  fi
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

is_managed_shared_path() {
  changed_path=$1

  case "$changed_path" in
    .codex|.codex/*)
      managed_root=$worktree_shared_root/.codex
      ;;
    .claude|.claude/*)
      managed_root=$worktree_shared_root/.claude
      ;;
    .direnv|.direnv/*)
      managed_root=$worktree_shared_root/.direnv
      ;;
    *)
      return 1
      ;;
  esac

  resolved_changed_path=$(realpath -m "$worktree_path/$changed_path")
  resolved_managed_root=$(realpath -m "$managed_root")

  case "$resolved_changed_path" in
    "$resolved_managed_root"|"$resolved_managed_root"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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
        allowed_write_roots="$allowed_write_roots $resolved_path"
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
      check_runtime_budget
      set +e
      suite_output=$(timeout "$remaining_runtime_secs" @SESSION_BIN@ validate --session-id "$session_id" "$suite_name")
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
          if [ "$suite_status" -eq 124 ]; then
            block_attempt "policy-runtime-limit"
          fi
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
  check_runtime_budget
  mkdir -p "$review_dir"
  diff_check_log=$review_dir/diff-check.log
  diff_stat_log=$review_dir/diff-stat.log
  conflicts_log=$review_dir/conflicts.log
  status_log=$review_dir/status.log
  changed_paths_log=$review_dir/changed-paths.log
  repo_changed_paths_log=$review_dir/changed-paths.filtered.log
  managed_shared_paths_log=$review_dir/managed-shared-paths.log
  scope_check_log=$review_dir/write-scope.log

  git -C "$worktree_path" status --porcelain >"$status_log"
  git -C "$worktree_path" diff --stat >"$diff_stat_log"
  git -C "$worktree_path" diff --name-only --diff-filter=U >"$conflicts_log"
  {
    git -C "$worktree_path" diff --name-only
    git -C "$worktree_path" ls-files --others --exclude-standard
    for managed_dir in .codex .claude .direnv; do
      if [ -e "$worktree_path/$managed_dir" ]; then
        find -L "$worktree_path/$managed_dir" -mindepth 1 -type f -printf '%P\n' | sed "s#^#$managed_dir/#"
      fi
    done
  } | sort -u >"$changed_paths_log"

  set +e
  git -C "$worktree_path" diff --check >"$diff_check_log" 2>&1
  diff_check_status=$?
  set -e
  check_runtime_budget

  : >"$repo_changed_paths_log"
  : >"$managed_shared_paths_log"
  while IFS= read -r changed_path; do
    [ -n "$changed_path" ] || continue
    case "$changed_path" in
      result|result/*|*.img|*.socket)
        continue
        ;;
    esac

    if is_managed_shared_path "$changed_path"; then
        printf '%s\n' "$changed_path" >>"$managed_shared_paths_log"
        continue
    fi

    printf '%s\n' "$changed_path" >>"$repo_changed_paths_log"
  done <"$changed_paths_log"

  conflict_count=$(wc -l <"$conflicts_log" | tr -d ' ')
  diff_check_count=$(wc -l <"$diff_check_log" | tr -d ' ')
  managed_shared_path_count=$(wc -l <"$managed_shared_paths_log" | tr -d ' ')
  scope_violation_count=0

  review_result="passed"
  : >"$scope_check_log"
  while IFS= read -r changed_path; do
    [ -n "$changed_path" ] || continue
    resolved_changed_path=$(realpath -m "$worktree_path/$changed_path")
    changed_path_allowed=0
    for allowed_root in $allowed_write_roots; do
      case "$resolved_changed_path" in
        "$allowed_root"|"$allowed_root"/*)
          changed_path_allowed=1
          break
          ;;
      esac
    done

    if [ "$changed_path_allowed" = "0" ]; then
      printf '%s\t%s\n' "$changed_path" "$resolved_changed_path" >>"$scope_check_log"
      scope_violation_count=$((scope_violation_count + 1))
    fi
  done <"$repo_changed_paths_log"

  if [ "$diff_check_status" -ne 0 ] || [ "$conflict_count" -ne 0 ]; then
    review_result="failed"
  fi
  if [ "$scope_violation_count" -ne 0 ]; then
    review_result="failed"
  fi

  cat >"$review_path" <<EOF
{
  "session_id": "$(json_escape "$session_id")",
  "review_result": "$(json_escape "$review_result")",
  "diff_check_status": $diff_check_status,
  "diff_check_line_count": $diff_check_count,
  "conflict_count": $conflict_count,
  "managed_shared_path_count": $managed_shared_path_count,
  "scope_violation_count": $scope_violation_count,
  "status_path": "$(json_escape "$status_log")",
  "diff_stat_path": "$(json_escape "$diff_stat_log")",
  "diff_check_path": "$(json_escape "$diff_check_log")",
  "conflicts_path": "$(json_escape "$conflicts_log")",
  "changed_paths_path": "$(json_escape "$repo_changed_paths_log")",
  "managed_shared_paths_path": "$(json_escape "$managed_shared_paths_log")",
  "write_scope_path": "$(json_escape "$scope_check_log")"
}
EOF

  check_runtime_budget
  if [ "$scope_violation_count" -ne 0 ]; then
    block_attempt "policy-write-scope"
  fi
  if [ "$review_result" != "passed" ]; then
    block_attempt "review-failed"
  fi
}

create_commit() {
  if [ -z "$commit_message" ]; then
    return 0
  fi

  check_runtime_budget
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
  max_parallelism=${FIREBREAK_AUTONOMY_MAX_PARALLELISM:-1}
  max_runtime_secs=${FIREBREAK_AUTONOMY_MAX_RUNTIME_SECS:-3600}
  validation_retry_budget=${FIREBREAK_AUTONOMY_VALIDATION_RETRIES:-0}
  allowed_write_roots=""

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
  started_epoch=$(date -u +%s)
  result="completed"
  blocked_reason=""
  commit_sha=""
  spec_path=""

  mkdir -p "$attempt_root"
  resolve_spec_path
  emit_plan

  active_root=$state_dir/autonomy-active
  active_guard=$state_dir/autonomy-active.guard
  active_lock=$active_root/$attempt_id
  mkdir -p "$active_root"
  guard_acquired=0
  for _ in $(seq 1 50); do
    if mkdir "$active_guard" 2>/dev/null; then
      guard_acquired=1
      break
    fi
    sleep 0.1
  done
  if [ "$guard_acquired" = "0" ]; then
    printf 'could not acquire autonomy parallelism guard\n' >"$policy_path"
    block_attempt "policy-parallelism-limit"
  fi
  active_count=$(find "$active_root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  if [ "$active_count" -ge "$max_parallelism" ]; then
    printf 'active attempts %s exceeds limit %s\n' "$active_count" "$max_parallelism" >"$policy_path"
    rmdir "$active_guard"
    block_attempt "policy-parallelism-limit"
  fi
  mkdir "$active_lock"
  rmdir "$active_guard"
  cleanup_active_lock() {
    rm -rf "$active_lock"
  }
  trap cleanup_active_lock EXIT INT TERM

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
