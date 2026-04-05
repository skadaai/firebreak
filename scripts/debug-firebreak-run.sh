#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[debug-firebreak-run] %s\n' "$*" >&2
}

timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"

workload="${1:-codex}"
shift || true

extra_args=("$@")

debug_root="${FIREBREAK_DEBUG_TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/firebreak/debug}"
mkdir -p "$debug_root"
run_dir="$(mktemp -d "$debug_root/run.XXXXXX")"

summary_file="$run_dir/summary.txt"

printf 'log_dir=%s\n' "$run_dir"

record_summary() {
  printf '%s %s\n' "$(timestamp)" "$*" >>"$summary_file"
}

dump_command_context() {
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'repo_root=%s\n' "$repo_root"
    printf 'workload=%s\n' "$workload"
    printf 'pwd=%s\n' "$PWD"
    printf 'nix=%s\n' "$(command -v nix || printf 'not-found')"
    printf 'git=%s\n' "$(command -v git || printf 'not-found')"
    printf 'PATH=%s\n' "$PATH"
    printf 'NIX_CONFIG=%s\n' "${NIX_CONFIG:-}"
    printf 'FIREBREAK_FLAKE_REF=%s\n' "${FIREBREAK_FLAKE_REF:-}"
    printf 'FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG=%s\n' "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}"
    printf 'FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES=%s\n' "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}"
    printf 'FIREBREAK_STATE_MODE=%s\n' "${FIREBREAK_STATE_MODE:-}"
    printf 'FIREBREAK_STATE_ROOT=%s\n' "${FIREBREAK_STATE_ROOT:-}"
    printf 'FIREBREAK_CREDENTIAL_SLOT=%s\n' "${FIREBREAK_CREDENTIAL_SLOT:-}"
    printf 'CODEX_CREDENTIAL_SLOT=%s\n' "${CODEX_CREDENTIAL_SLOT:-}"
    printf 'CLAUDE_CREDENTIAL_SLOT=%s\n' "${CLAUDE_CREDENTIAL_SLOT:-}"
  } >"$run_dir/context.env"

  git -C "$repo_root" status --short >"$run_dir/git-status.txt" 2>&1 || true
}

run_step() {
  local step_name=$1
  shift

  local stdout_file="$run_dir/${step_name}.stdout.log"
  local stderr_file="$run_dir/${step_name}.stderr.log"
  local status_file="$run_dir/${step_name}.status"
  local argv_file="$run_dir/${step_name}.argv"

  printf '%q ' "$@" >"$argv_file"
  printf '\n' >>"$argv_file"

  log "START $step_name"
  record_summary "START $step_name"
  {
    printf 'step=%s\n' "$step_name"
    printf 'started_at=%s\n' "$(timestamp)"
    printf 'cwd=%s\n' "$repo_root"
    printf 'command='
    printf '%q ' "$@"
    printf '\n'
  } >"$run_dir/${step_name}.meta"

  set +e
  (
    cd "$repo_root"
    "$@"
  ) >"$stdout_file" 2>"$stderr_file"
  local status=$?
  set -e

  printf '%s\n' "$status" >"$status_file"
  {
    printf 'finished_at=%s\n' "$(timestamp)"
    printf 'exit_status=%s\n' "$status"
  } >>"$run_dir/${step_name}.meta"

  log "END $step_name status=$status"
  record_summary "END $step_name status=$status"
  return 0
}

print_step_excerpt() {
  local step_name=$1
  local stdout_file="$run_dir/${step_name}.stdout.log"
  local stderr_file="$run_dir/${step_name}.stderr.log"
  local status
  status="$(cat "$run_dir/${step_name}.status" 2>/dev/null || printf 'missing')"

  printf '\n== %s ==\n' "$step_name"
  printf 'status: %s\n' "$status"
  printf 'argv: '
  cat "$run_dir/${step_name}.argv" 2>/dev/null || printf '\n'

  if [ -s "$stdout_file" ]; then
    printf -- '-- stdout (first 80 lines) --\n'
    sed -n '1,80p' "$stdout_file"
  else
    printf -- '-- stdout: empty --\n'
  fi

  if [ -s "$stderr_file" ]; then
    printf -- '-- stderr (first 120 lines) --\n'
    sed -n '1,120p' "$stderr_file"
  else
    printf -- '-- stderr: empty --\n'
  fi
}

extract_build_output_path() {
  local stdout_file=$1
  awk 'NF { last=$0 } END { print last }' "$stdout_file"
}

dump_command_context

run_step build_firebreak \
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    build .#firebreak --print-out-paths --no-link --show-trace

build_out="$(extract_build_output_path "$run_dir/build_firebreak.stdout.log")"
printf '%s\n' "$build_out" >"$run_dir/build_firebreak.path"

if [ -n "$build_out" ] && [ -x "$build_out/bin/firebreak" ]; then
  run_step built_firebreak_header sed -n '1,120p' "$build_out/bin/firebreak"
  run_step built_firebreak_vms "$build_out/bin/firebreak" vms
  run_step built_firebreak_run timeout 20 "$build_out/bin/firebreak" run "$workload" "${extra_args[@]}"
else
  log "Skipping built_firebreak_* steps because build output is missing or not executable"
  record_summary "SKIP built_firebreak steps"
fi

run_step raw_nix_eval_name \
  nix --extra-experimental-features 'nix-command flakes' \
    eval --raw .#packages.x86_64-linux.firebreak.name --show-trace

run_step raw_nix_path_info \
  nix --extra-experimental-features 'nix-command flakes' \
    path-info .#firebreak --json --show-trace

run_step raw_nix_run_vms \
  nix --extra-experimental-features 'nix-command flakes' \
    run .#firebreak -- vms

run_step raw_nix_run_workload \
  nix --extra-experimental-features 'nix-command flakes' \
    run .#firebreak -- run "$workload" "${extra_args[@]}"

run_step trusted_nix_run_workload \
  timeout 20 \
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    run .#firebreak -- run "$workload" "${extra_args[@]}"

printf 'Firebreak debug run complete\n'
printf 'log_dir=%s\n' "$run_dir"
printf 'workload=%s\n' "$workload"

print_step_excerpt build_firebreak
if [ -n "${build_out:-}" ] && [ -x "${build_out:-}/bin/firebreak" ]; then
  print_step_excerpt built_firebreak_vms
  print_step_excerpt built_firebreak_run
fi
print_step_excerpt raw_nix_eval_name
print_step_excerpt raw_nix_path_info
print_step_excerpt raw_nix_run_vms
print_step_excerpt raw_nix_run_workload
print_step_excerpt trusted_nix_run_workload
