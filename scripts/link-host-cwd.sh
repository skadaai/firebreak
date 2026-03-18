set -eu

metadata=@HOST_META_MOUNT@/mount-path
for _ in $(seq 1 50); do
  if [ -d @WORKSPACE_MOUNT@ ] && [ -r "$metadata" ]; then
    break
  fi
  sleep 0.1
done

if ! [ -d @WORKSPACE_MOUNT@ ] || ! [ -r "$metadata" ]; then
  echo "workspace or host cwd metadata not ready; continuing without dynamic bind mount"
  exit 0
fi

target=$(cat "$metadata")
if [ -z "$target" ]; then
  exit 0
fi

printf '%s\n' "$target" > @START_DIR_FILE@
chmod 0644 @START_DIR_FILE@

if [ "$target" = "@WORKSPACE_MOUNT@" ]; then
  exit 0
fi

if [ -L "$target" ]; then
  rm -f "$target"
fi

if mountpoint -q "$target"; then
  exit 0
fi

parent=$(dirname "$target")
mkdir -p "$parent" "$target"

if [ -e "$target" ] && ! [ -d "$target" ]; then
  echo "refusing to replace existing non-directory path: $target"
  exit 0
fi

mount --bind @WORKSPACE_MOUNT@ "$target"
