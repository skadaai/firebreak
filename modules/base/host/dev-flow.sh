set -eu

dev_flow_libexec_dir=${DEV_FLOW_LIBEXEC_DIR:-${FIREBREAK_LIBEXEC_DIR:-}}
if [ -z "$dev_flow_libexec_dir" ]; then
  dev_flow_libexec_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fi

command=${1:-}

. "$dev_flow_libexec_dir/firebreak-project-config.sh"

dev_flow_require_flake_ref() {
  if [ -z "${DEV_FLOW_FLAKE_REF:-${FIREBREAK_FLAKE_REF:-}}" ]; then
    echo "DEV_FLOW_FLAKE_REF is required for commands that launch dev-flow workloads" >&2
    exit 1
  fi
}

dev_flow_exec_package() {
  package_name=$1
  shift

  dev_flow_require_flake_ref
  flake_ref=${DEV_FLOW_FLAKE_REF:-${FIREBREAK_FLAKE_REF:-}}
  accept_flake_config=${DEV_FLOW_NIX_ACCEPT_FLAKE_CONFIG:-${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}}
  extra_experimental_features=${DEV_FLOW_NIX_EXTRA_EXPERIMENTAL_FEATURES:-${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}}

  if [ "$accept_flake_config" = "1" ] && [ -n "$extra_experimental_features" ]; then
    exec nix --accept-flake-config --extra-experimental-features "$extra_experimental_features" \
      run "$flake_ref#$package_name" -- "$@"
  fi

  if [ "$accept_flake_config" = "1" ]; then
    exec nix --accept-flake-config run "$flake_ref#$package_name" -- "$@"
  fi

  if [ -n "$extra_experimental_features" ]; then
    exec nix --extra-experimental-features "$extra_experimental_features" \
      run "$flake_ref#$package_name" -- "$@"
  fi

  exec nix run "$flake_ref#$package_name" -- "$@"
}

usage() {
  cat <<'EOF'
Skada dev-flow

usage:
  dev-flow validate run SUITE [--state-dir PATH]
  dev-flow workspace <subcommand> ...
  dev-flow loop run ...

Available commands:
  validate    Run named validation suites for workflow evidence
  workspace   Create, inspect, validate, and close isolated workspaces
  loop        Run the bounded attempt loop against an existing workspace
EOF
}

case "$command" in
  validate)
    shift
    dev_flow_exec_package "dev-flow-validate" "$@"
    ;;
  workspace)
    shift
    dev_flow_exec_package "dev-flow-workspace" "$@"
    ;;
  loop)
    shift
    dev_flow_exec_package "dev-flow-loop" "$@"
    ;;
  ""|--help|-h|help)
    usage
    ;;
  *)
    echo "unknown dev-flow subcommand: $command" >&2
    exit 1
    ;;
esac
