set -eu

dev_home=@DEV_HOME@
dev_user=@DEV_USER@
local_bin=@LOCAL_BIN@
xdg_config_home=@XDG_CONFIG_HOME@
xdg_cache_home=@XDG_CACHE_HOME@
xdg_state_home=@XDG_STATE_HOME@
npm_cache_dir=@NPM_CACHE_DIR@
install_tmp=@TMPDIR@
install_prefix="$dev_home/.local"
package_node_modules=@PACKAGE_NODE_MODULES@
state_root="$dev_home/.cache/firebreak-tools/@NAME@"
state_file="$state_root/package-spec"

mkdir -p \
  "$state_root" \
  "$local_bin" \
  "$install_prefix" \
  "$install_prefix/lib/node_modules" \
  "$install_tmp" \
  "$xdg_config_home" \
  "$xdg_cache_home" \
  "$xdg_state_home" \
  "$npm_cache_dir"
chown -R "$dev_user:$dev_user" "$dev_home"

if [ -x "$local_bin/@BIN_NAME@" ] && [ -r "$state_file" ] && [ "$(cat "$state_file")" = '@PACKAGE_SPEC@' ]; then
  printf '%s\n' '@DISPLAY_NAME@: packaged CLI already installed.'
  exit 0
fi

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
  sh -lc '
    set -eu
    mkdir -p \
      "$XDG_CONFIG_HOME" \
      "$XDG_CACHE_HOME" \
      "$XDG_STATE_HOME" \
      "$npm_config_cache" \
      "$npm_config_prefix"
    rm -rf "$1"
    rm -f "$npm_config_prefix/bin/@BIN_NAME@"
    npm install --global --omit=dev "$2"
  ' sh "$package_node_modules" '@PACKAGE_SPEC@'

printf '%s\n' '@PACKAGE_SPEC@' > "$state_file"
chown -R "$dev_user:$dev_user" "$state_root" "$dev_home"
printf '%s\n' '@DISPLAY_NAME@: packaged CLI installed.'
