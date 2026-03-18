set -eu

warn() {
  echo "$*" >&2
}

lookup_group_by_gid() {
  target="$1"
  while IFS=: read -r name _ gid _; do
    if [ "$gid" = "$target" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done < /etc/group
  return 1
}

lookup_user_by_uid() {
  target="$1"
  while IFS=: read -r name _ uid _ _ _ _; do
    if [ "$uid" = "$target" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done < /etc/passwd
  return 1
}

uid_file=@HOST_META_MOUNT@/host-uid
gid_file=@HOST_META_MOUNT@/host-gid

if ! [ -r "$uid_file" ] || ! [ -r "$gid_file" ]; then
  exit 0
fi

target_uid=$(@CAT@ "$uid_file")
target_gid=$(@CAT@ "$gid_file")

case "$target_uid" in
  ''|*[!0-9]*)
    echo "ignoring invalid host uid: $target_uid" >&2
    exit 0
    ;;
esac

case "$target_gid" in
  ''|*[!0-9]*)
    echo "ignoring invalid host gid: $target_gid" >&2
    exit 0
    ;;
esac

current_uid=$(@ID@ -u @DEV_USER@)
current_gid=$(@ID@ -g @DEV_USER@)
target_group_name=@DEV_USER@

if [ "$current_gid" != "$target_gid" ]; then
  existing_group_name=$(lookup_group_by_gid "$target_gid" || true)
  if [ -n "$existing_group_name" ] && [ "$existing_group_name" != "@DEV_USER@" ]; then
    target_group_name=$existing_group_name
  else
    if ! @GROUPMOD@ -g "$target_gid" @DEV_USER@; then
      warn "could not change @DEV_USER@ group to gid $target_gid; keeping guest gid $current_gid"
    fi
  fi
fi

if [ "$current_uid" != "$target_uid" ]; then
  existing_user_name=$(lookup_user_by_uid "$target_uid" || true)
  if [ -n "$existing_user_name" ] && [ "$existing_user_name" != "@DEV_USER@" ]; then
    warn "host uid $target_uid is already used by $existing_user_name in the guest; keeping guest uid $current_uid"
  else
    if ! @USERMOD@ -u "$target_uid" @DEV_USER@; then
      warn "could not change @DEV_USER@ uid to $target_uid; keeping guest uid $current_uid"
    fi
  fi
fi

current_group_name=$(@ID@ -gn @DEV_USER@)
if [ "$current_group_name" != "$target_group_name" ]; then
  if ! @USERMOD@ -g "$target_group_name" @DEV_USER@; then
    warn "could not switch @DEV_USER@ primary group to $target_group_name"
  fi
fi

if ! @CHOWN@ -R @DEV_USER@:"$target_group_name" @DEV_HOME@; then
  warn "could not fully normalize ownership under @DEV_HOME@"
fi
