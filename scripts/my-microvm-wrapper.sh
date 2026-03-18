set -eu

host_cwd=$PWD
case "$host_cwd" in
  *[[:space:]]*)
    echo "current working directory contains whitespace, which microvm runtime share injection does not support: $host_cwd" >&2
    exit 1
    ;;
esac

host_meta_dir=$(mktemp -d)
trap 'rm -rf "$host_meta_dir"' EXIT INT TERM

printf '%s\n' "$host_cwd" > "$host_meta_dir/mount-path"

exec env \
  MICROVM_HOST_CWD="$host_cwd" \
  MICROVM_HOST_META_DIR="$host_meta_dir" \
  @RUNNER@ "$@"
