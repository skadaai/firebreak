#!/usr/bin/env bash
set -eu

dev_home=@DEV_HOME@
dev_user=@DEV_USER@
tool_home=$dev_home
if [ -d @AGENT_TOOLS_MOUNT@ ]; then
  tool_home=@AGENT_TOOLS_MOUNT@
fi

local_bin="$tool_home/.local/bin"
xdg_config_home="$tool_home/.config"
xdg_cache_home="$tool_home/.cache"
xdg_state_home="$tool_home/.local/state"
npm_cache_dir="$xdg_cache_home/npm"
install_tmp="$xdg_cache_home/tmp"
install_prefix="$tool_home/.local"
package_spec='@PACKAGE_SPEC@'
package_node_modules="$install_prefix/lib/node_modules/$package_spec"
state_root="$xdg_state_home/firebreak-node-cli/@NAME@"
state_file="$state_root/install-state"
ready_marker=@BOOTSTRAP_READY_MARKER@
install_state_id='@INSTALL_STATE_ID@'
bootstrap_state_dir=/run/firebreak-agent
bootstrap_state_path="$bootstrap_state_dir/bootstrap-state.json"
shared_bootstrap_state_path="@AGENT_EXEC_OUTPUT_MOUNT@/bootstrap-state.json"
shared_tool_home=0
if [ "$tool_home" != "$dev_home" ]; then
  shared_tool_home=1
fi

log_phase() {
  printf '[firebreak-bootstrap] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_bootstrap_state() {
  bootstrap_phase=$1
  bootstrap_status=$2
  bootstrap_detail=$3
  updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat >"$bootstrap_state_path" <<EOF
{
  "source": "guest-bootstrap",
  "phase": "$(json_escape "$bootstrap_phase")",
  "status": "$(json_escape "$bootstrap_status")",
  "detail": "$(json_escape "$bootstrap_detail")",
  "agent_bin": "@BIN_NAME@",
  "package_spec": "$(json_escape "$package_spec")",
  "updated_at": "$updated_at"
}
EOF
  if [ -d "@AGENT_EXEC_OUTPUT_MOUNT@" ]; then
    cp "$bootstrap_state_path" "$shared_bootstrap_state_path" 2>/dev/null || true
  fi
}

ensure_dir() {
  target_path=$1
  mkdir -p "$target_path"
  chmod 0755 "$target_path" 2>/dev/null || true
}

maybe_chown_dev() {
  target_path=$1
  if [ "$(id -u)" -ne 0 ]; then
    return 0
  fi
  if chown "$dev_user:$dev_user" "$target_path" 2>/dev/null; then
    return 0
  fi
  if [ "$shared_tool_home" = "1" ]; then
    log_phase "ownership-skip $target_path"
    return 0
  fi
  echo "failed to chown bootstrap-managed path: $target_path" >&2
  return 1
}

write_ready_marker() {
  ready_dir=$(dirname "$ready_marker")
  ready_tmp=$(mktemp "$ready_dir/.bootstrap-ready.XXXXXX")
  printf '%s
' "$install_state_id" >"$ready_tmp"
  mv -f "$ready_tmp" "$ready_marker"
}

wrappers_ready() {
  for wrapper_name in @INSTALL_BIN_NAMES@; do
    if [ ! -x "$local_bin/$wrapper_name" ]; then
      return 1
    fi
  done
  return 0
}

current_bootstrap_phase=init
bootstrap_trap() {
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    rm -f "$ready_marker"
    write_bootstrap_state "$current_bootstrap_phase" "error" "bootstrap-exit:$exit_code"
  fi
  exit "$exit_code"
}
trap bootstrap_trap EXIT

log_phase "toolchain-prepare-start @DISPLAY_NAME@"
log_phase "tool-home $tool_home"
log_phase "tool-ready-marker $ready_marker"
ensure_dir "$bootstrap_state_dir"
ensure_dir "$(dirname "$ready_marker")"
current_bootstrap_phase=toolchain-prepare-start
write_bootstrap_state "$current_bootstrap_phase" "running" "@DISPLAY_NAME@"

for bootstrap_dir in \
  "$state_root" \
  "$local_bin" \
  "$install_prefix" \
  "$install_prefix/lib/node_modules" \
  "$install_tmp" \
  "$xdg_config_home" \
  "$xdg_cache_home" \
  "$xdg_state_home" \
  "$npm_cache_dir"; do
  ensure_dir "$bootstrap_dir"
done

for bootstrap_dir in \
  "$state_root" \
  "$local_bin" \
  "$install_prefix" \
  "$install_prefix/lib/node_modules" \
  "$install_tmp" \
  "$xdg_config_home" \
  "$xdg_cache_home" \
  "$xdg_state_home" \
  "$npm_cache_dir"; do
  chown "$dev_user:$dev_user" "$bootstrap_dir"
done

if [ -x "$local_bin/@BIN_NAME@" ] && [ -r "$state_file" ] && [ "$(cat "$state_file")" = "$install_state_id" ] && [ -r "$ready_marker" ] && wrappers_ready; then
  log_phase "toolchain-cache-hit $package_spec"
  current_bootstrap_phase=toolchain-cache-hit
  write_bootstrap_state "$current_bootstrap_phase" "running" "$package_spec"
  log_phase "wrapper-ready @BIN_NAME@"
  current_bootstrap_phase=wrapper-ready
  write_bootstrap_state "$current_bootstrap_phase" "ready" "@BIN_NAME@"
  exit 0
fi

rm -f "$ready_marker"

current_bootstrap_phase=toolchain-install-start
write_bootstrap_state "$current_bootstrap_phase" "running" "$package_spec"
log_phase "toolchain-install-start $package_spec"

runuser -u "$dev_user" -- env \
  HOME="$dev_home" \
  XDG_CONFIG_HOME="$xdg_config_home" \
  XDG_CACHE_HOME="$xdg_cache_home" \
  XDG_STATE_HOME="$xdg_state_home" \
  TMPDIR="$install_tmp" \
  npm_config_cache="$npm_cache_dir" \
  npm_config_prefix="$install_prefix" \
  npm_config_audit=false \
  npm_config_fund=false \
  npm_config_update_notifier=false \
  npm_config_loglevel=warn \
  CI=1 \
  PATH="$local_bin:$PATH" \
  sh -s "$package_node_modules" "$package_spec" <<'EOF'
set -eu
mkdir -p \
  "$XDG_CONFIG_HOME" \
  "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME" \
  "$npm_config_cache" \
  "$npm_config_prefix"
rm -rf "$1"
rm -f "$npm_config_prefix/bin/@BIN_NAME@"
set -- "$2" @PROXY_LOCAL_UPSTREAM_INSTALL_ARGS@
npm install --global --omit=dev "$@"
@POST_INSTALL_SCRIPT@
@INSTALL_BIN_SCRIPTS@
EOF

printf '%s\n' "$install_state_id" > "$state_file"
write_ready_marker
maybe_chown_dev "$state_file"
maybe_chown_dev "$ready_marker"

log_phase "toolchain-install-done $package_spec"
current_bootstrap_phase=toolchain-install-done
write_bootstrap_state "$current_bootstrap_phase" "running" "$package_spec"
log_phase "wrapper-ready @BIN_NAME@"
current_bootstrap_phase=wrapper-ready
write_bootstrap_state "$current_bootstrap_phase" "ready" "@BIN_NAME@"
printf '%s\n' '@DISPLAY_NAME@: packaged CLI installed.'
