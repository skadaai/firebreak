# shellcheck shell=sh
profile_guest_events_file=@COMMAND_OUTPUT_MOUNT@/profile-guest.tsv

firebreak_profile_now_ms() {
  date -u +%s%3N
}

firebreak_profile_sanitize_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

firebreak_profile_guest_mark() {
  local profile_component profile_phase profile_detail
  profile_component=$1
  profile_phase=$2
  profile_detail=${3:-}

  if ! [ -d @COMMAND_OUTPUT_MOUNT@ ]; then
    return 0
  fi

  printf '%s\t%s\t%s\t%s\n' \
    "$(firebreak_profile_now_ms)" \
    "$(firebreak_profile_sanitize_field "$profile_component")" \
    "$(firebreak_profile_sanitize_field "$profile_phase")" \
    "$(firebreak_profile_sanitize_field "$profile_detail")" \
    >>"$profile_guest_events_file" 2>/dev/null || true
}
