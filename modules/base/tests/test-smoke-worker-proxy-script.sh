#!/usr/bin/env bash
set -eu

tmp_root=${TMPDIR:-/tmp}
smoke_dir=$(mktemp -d "$tmp_root/firebreak-worker-proxy.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT INT TERM

mkdir -p "$smoke_dir/bin"
mkdir -p "$smoke_dir/local-bin"

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

wrapper_info_output=$(FIREBREAK_WRAPPER_INFO=1 codex)
require_pattern "$wrapper_info_output" '"wrapper": "firebreak"' "wrapper info identity"
require_pattern "$wrapper_info_output" '"command": "codex"' "wrapper info command"
require_pattern "$wrapper_info_output" '"resolved_mode": "local"' "wrapper info default mode"

default_version_output=$(codex --version)
require_pattern "$default_version_output" "__UPSTREAM__--version" "default upstream version dispatch"

local_version_output=$(FIREBREAK_WORKER_MODE=local codex --version)
require_pattern "$local_version_output" "__UPSTREAM__--version" "local upstream version dispatch"

worker_wrapper_info_output=$(FIREBREAK_WORKER_MODE=vm FIREBREAK_WRAPPER_INFO=1 codex)
require_pattern "$worker_wrapper_info_output" '"resolved_mode": "vm"' "wrapper info vm mode"

default_output=$(codex --help)
require_pattern "$default_output" "__UPSTREAM__--help" "default local dispatch"

worker_output=$(FIREBREAK_WORKER_MODE=vm codex --help)
require_pattern "$worker_output" "__WORKER__worker run --kind codex --workspace" "worker dispatch prefix"
require_pattern "$worker_output" "-- --help" "worker dispatch arguments"
if printf '%s\n' "$worker_output" | grep -F -q -- "--attach -- --help"; then
  printf '%s\n' "$worker_output" >&2
  echo "worker help dispatch should not force attach mode" >&2
  exit 1
fi

local_output=$(FIREBREAK_WORKER_MODE=local codex --help)
require_pattern "$local_output" "__UPSTREAM__--help" "local upstream dispatch"

mv "$smoke_dir/bin/.firebreak-upstream-codex" "$smoke_dir/local-bin/.firebreak-upstream-codex"
fallback_output=$(LOCAL_BIN="$smoke_dir/local-bin" FIREBREAK_WORKER_MODE=local codex --help)
require_pattern "$fallback_output" "__UPSTREAM__--help" "local-bin upstream fallback dispatch"

per_worker_output=$(FIREBREAK_WORKER_MODE=local FIREBREAK_WORKER_MODES=codex=vm codex --help)
require_pattern "$per_worker_output" "__WORKER__worker run --kind codex --workspace" "per-worker override precedence"
if printf '%s\n' "$per_worker_output" | grep -F -q -- "--attach -- --help"; then
  printf '%s\n' "$per_worker_output" >&2
  echo "per-worker help dispatch should not force attach mode" >&2
  exit 1
fi

worker_version_output=$(FIREBREAK_WORKER_MODE=vm codex --version)
require_pattern "$worker_version_output" "__WORKER__worker run --kind codex --workspace" "worker version dispatch prefix"
require_pattern "$worker_version_output" "-- --version" "worker version dispatch arguments"
if printf '%s\n' "$worker_version_output" | grep -F -q -- "--attach -- --version"; then
  printf '%s\n' "$worker_version_output" >&2
  echo "worker version dispatch should not force attach mode" >&2
  exit 1
fi

set +e
invalid_mode_output=$(FIREBREAK_WORKER_MODE=invalid codex --help 2>&1)
invalid_mode_status=$?
set -e

if [ "$invalid_mode_status" -eq 0 ]; then
  printf '%s\n' "$invalid_mode_output" >&2
  echo "worker proxy script accepted an invalid FIREBREAK_WORKER_MODE" >&2
  exit 1
fi

require_pattern "$invalid_mode_output" "unsupported FIREBREAK_WORKER_MODE" "invalid mode rejection"

printf '%s\n' "Firebreak worker proxy script smoke test passed"
