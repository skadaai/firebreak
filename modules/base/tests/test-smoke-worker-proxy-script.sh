set -eu

tmp_root=${TMPDIR:-/tmp}
smoke_dir=$(mktemp -d "$tmp_root/firebreak-worker-proxy.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT INT TERM

mkdir -p "$smoke_dir/bin"

cat >"$smoke_dir/bin/firebreak" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "__WORKER__$*"
EOF
chmod 0755 "$smoke_dir/bin/firebreak"

cat >"$smoke_dir/bin/.firebreak-upstream-codex" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "__UPSTREAM__$*"
EOF
chmod 0755 "$smoke_dir/bin/.firebreak-upstream-codex"

cat >"$smoke_dir/bin/codex" <<'EOF'
@WORKER_PROXY_SCRIPT@
EOF
chmod 0755 "$smoke_dir/bin/codex"

PATH="$smoke_dir/bin:$PATH"
export PATH

require_pattern() {
  output=$1
  pattern=$2
  description=$3

  if ! printf '%s\n' "$output" | grep -F -q -- "$pattern"; then
    printf '%s\n' "$output" >&2
    echo "missing $description" >&2
    exit 1
  fi
}

worker_version_output=$(codex --version)
require_pattern "$worker_version_output" "codex firebreak worker proxy" "worker proxy version output"

worker_output=$(FIREBREAK_WORKER_PROXY_MODE=worker codex --help)
require_pattern "$worker_output" "__WORKER__worker run --kind codex --workspace" "worker dispatch prefix"
require_pattern "$worker_output" "--attach -- --help" "worker dispatch arguments"

local_output=$(FIREBREAK_WORKER_PROXY_MODE=local codex --help)
require_pattern "$local_output" "__UPSTREAM__--help" "local upstream dispatch"

set +e
invalid_mode_output=$(FIREBREAK_WORKER_PROXY_MODE=invalid codex --help 2>&1)
invalid_mode_status=$?
set -e

if [ "$invalid_mode_status" -eq 0 ]; then
  printf '%s\n' "$invalid_mode_output" >&2
  echo "worker proxy script accepted an invalid FIREBREAK_WORKER_PROXY_MODE" >&2
  exit 1
fi

require_pattern "$invalid_mode_output" "unsupported FIREBREAK_WORKER_PROXY_MODE" "invalid mode rejection"

printf '%s\n' "Firebreak worker proxy script smoke test passed"
