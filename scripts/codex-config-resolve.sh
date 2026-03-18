set -eu

mode_file=@HOST_META_MOUNT@/codex-config-mode
start_dir=@WORKSPACE_MOUNT@
resolved_dir=@DEV_HOME@/.codex
mode=vm

if [ -r @START_DIR_FILE@ ]; then
  start_dir=$(cat @START_DIR_FILE@)
fi

if [ -r "$mode_file" ]; then
  mode=$(cat "$mode_file")
fi

case "$mode" in
  host)
    mkdir -p @CODEX_CONFIG_HOST_MOUNT@
    if ! mountpoint -q @CODEX_CONFIG_HOST_MOUNT@; then
      if ! mount -t virtiofs hostcodexconfig @CODEX_CONFIG_HOST_MOUNT@; then
        echo "failed to mount host Codex config share; falling back to vm config" >&2
        mode=vm
        mkdir -p "$resolved_dir"
        chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
      fi
    fi

    if [ "$mode" = "host" ]; then
      resolved_dir=@CODEX_CONFIG_HOST_MOUNT@
    fi
    ;;
  workspace)
    resolved_dir=$start_dir/.codex
    ;;
  vm)
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
  fresh)
    resolved_dir=@CODEX_FRESH_CONFIG_DIR@
    rm -rf "$resolved_dir"
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
  *)
    echo "unsupported Codex config mode '$mode'; falling back to vm" >&2
    mode=vm
    mkdir -p "$resolved_dir"
    chown @DEV_USER@:@DEV_USER@ "$resolved_dir"
    ;;
esac

printf '%s\n' "$resolved_dir" > @CODEX_CONFIG_DIR_FILE@
chmod 0644 @CODEX_CONFIG_DIR_FILE@
