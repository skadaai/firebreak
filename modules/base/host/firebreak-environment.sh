firebreak_environment_usage() {
  cat <<'EOF' >&2
usage:
  firebreak environment resolve [--json]
EOF
  exit 1
}

firebreak_environment_hash_string() {
  value=$1
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | cut -d' ' -f1
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$value" | shasum -a 256 | cut -d' ' -f1
    return 0
  fi

  echo "missing sha256 tool" >&2
  return 1
}

firebreak_environment_python() {
  if [ -n "${PYTHON3:-}" ]; then
    printf '%s\n' "$PYTHON3"
    return 0
  fi
  printf '%s\n' "python3"
}

firebreak_environment_hash_file() {
  file_path=$1
  if ! [ -f "$file_path" ]; then
    return 1
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | cut -d' ' -f1
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | cut -d' ' -f1
    return 0
  fi

  echo "missing sha256 tool" >&2
  return 1
}

firebreak_environment_json_escape() {
  value=$1
  value=$(printf '%s' "$value" | awk 'BEGIN { ORS = "" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\n/, "\\n"); print }')
  printf '%s' "$value"
}

firebreak_reset_environment_state() {
  FIREBREAK_RESOLVED_ENVIRONMENT_MODE=""
  FIREBREAK_RESOLVED_ENVIRONMENT_KIND=""
  FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE="none"
  FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE=""
  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED="0"
  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE="none"
  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH=""
  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_FLAKE_FILE=""
  FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_ROOT=""
  FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR=""
  FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE=""
  FIREBREAK_RESOLVED_ENVIRONMENT_MANIFEST_FILE=""
  FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY=""
  FIREBREAK_RESOLVED_ENVIRONMENT_REUSED="0"
  FIREBREAK_RESOLVED_ENVIRONMENT_READY="0"
  FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON='[]'
  FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON='{}'
  FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY=""
  FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE=""
  FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION=""
}

firebreak_environment_nix_command() {
  nix_subcommand=$1
  shift

  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ] \
    && [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    nix --accept-flake-config --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" "$nix_subcommand" --no-write-lock-file "$@"
    return
  fi

  if [ "${FIREBREAK_NIX_ACCEPT_FLAKE_CONFIG:-}" = "1" ]; then
    nix --accept-flake-config "$nix_subcommand" --no-write-lock-file "$@"
    return
  fi

  if [ -n "${FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES:-}" ]; then
    nix --extra-experimental-features "$FIREBREAK_NIX_EXTRA_EXPERIMENTAL_FEATURES" "$nix_subcommand" --no-write-lock-file "$@"
    return
  fi

  nix "$nix_subcommand" --no-write-lock-file "$@"
}

firebreak_environment_mode_allowed() {
  case "$1" in
    ""|auto|off|devshell|package)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

firebreak_environment_installable_kind() {
  installable=$1
  case "$installable" in
    *devShell*|*devshell*)
      printf '%s\n' "devshell"
      ;;
    *)
      printf '%s\n' "package"
      ;;
  esac
}

firebreak_environment_resolve_explicit_installable() {
  explicit_installable=${FIREBREAK_ENVIRONMENT_INSTALLABLE:-}
  if [ -z "$explicit_installable" ]; then
    return 1
  fi

  case "$explicit_installable" in
    .#*)
      printf 'path:%s%s\n' "$FIREBREAK_RESOLVED_PROJECT_ROOT" "${explicit_installable#.}"
      ;;
    \#*)
      printf 'path:%s%s\n' "$FIREBREAK_RESOLVED_PROJECT_ROOT" "$explicit_installable"
      ;;
    *)
      printf '%s\n' "$explicit_installable"
      ;;
  esac
}

firebreak_environment_try_eval() {
  installable=$1
  mode=$2

  case "$mode" in
    devshell)
      firebreak_environment_nix_command print-dev-env --json "$installable" >/dev/null 2>&1
      ;;
    package)
      firebreak_environment_nix_command build --no-link --print-out-paths "$installable" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

firebreak_environment_detect_project_installable() {
  if [ "${FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED:-0}" != "1" ]; then
    return 1
  fi

  project_flake_file=$FIREBREAK_RESOLVED_PROJECT_ROOT/flake.nix
  if ! [ -f "$project_flake_file" ]; then
    return 1
  fi

  project_flake_ref="path:$FIREBREAK_RESOLVED_PROJECT_ROOT"
  host_system=${FIREBREAK_HOST_SYSTEM:-$(uname -m | tr '[:upper:]' '[:lower:]')-linux}
  default_devshell="$project_flake_ref#devShells.$host_system.default"
  default_package="$project_flake_ref#packages.$host_system.default"

  if firebreak_environment_try_eval "$default_devshell" devshell; then
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE="devShells.$host_system.default"
    printf '%s|%s\n' "devshell" "$default_devshell"
    return 0
  fi

  if firebreak_environment_try_eval "$default_package" package; then
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE="packages.$host_system.default"
    printf '%s|%s\n' "package" "$default_package"
    return 0
  fi

  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE="none"
  return 1
}

firebreak_environment_resolve_cache_paths() {
  if [ -n "${FIREBREAK_ENVIRONMENT_CACHE_ROOT:-}" ]; then
    FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_ROOT=$FIREBREAK_ENVIRONMENT_CACHE_ROOT
  else
    FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_ROOT=${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}/firebreak/environments
  fi
  mkdir -p "$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_ROOT"

  identity_material=$(
    FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE=$FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE \
      FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE=$FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE \
      FIREBREAK_RESOLVED_ENVIRONMENT_KIND=$FIREBREAK_RESOLVED_ENVIRONMENT_KIND \
      FIREBREAK_RESOLVED_ENVIRONMENT_MODE=$FIREBREAK_RESOLVED_ENVIRONMENT_MODE \
      FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON \
      FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY \
      FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON \
      FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH=$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH \
      FIREBREAK_RESOLVED_PROJECT_ROOT=$FIREBREAK_RESOLVED_PROJECT_ROOT \
      FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION=$FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION \
      "$(firebreak_environment_python)" - <<'PY'
import json
import os

payload = {
    "boot_base": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE", ""),
    "installable": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE", ""),
    "kind": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_KIND", ""),
    "mode": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_MODE", ""),
    "package_exports_json": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON", "{}"),
    "package_identity": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY", ""),
    "package_paths_json": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON", "[]"),
    "project_lock_hash": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH", ""),
    "project_root": os.environ.get("FIREBREAK_RESOLVED_PROJECT_ROOT", ""),
    "runtime_version": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION", ""),
}
print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
PY
  )
  FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY=$(firebreak_environment_hash_string "$identity_material")
  FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR=$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_ROOT/$FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY
  FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE=$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR/environment.sh
  FIREBREAK_RESOLVED_ENVIRONMENT_MANIFEST_FILE=$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR/manifest.json
}

firebreak_environment_write_package_overlay() {
  target_file=$1

  PACKAGE_EXPORTS_JSON=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON \
    PACKAGE_PATHS_JSON=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON \
    "$(firebreak_environment_python)" - "$target_file" <<'PY'
import json
import os
import shlex
import sys
from pathlib import Path

target_path = Path(sys.argv[1])
path_entries = json.loads(os.environ["PACKAGE_PATHS_JSON"])
exports = json.loads(os.environ["PACKAGE_EXPORTS_JSON"])

with target_path.open("a", encoding="utf-8") as handle:
    for entry in path_entries:
        handle.write(f'if [ -d {shlex.quote(entry)} ]; then export PATH={shlex.quote(entry)}:"$PATH"; fi\n')
    for key, value in sorted(exports.items()):
        handle.write(f'export {key}={shlex.quote(str(value))}\n')
PY
}

firebreak_environment_write_devshell_overlay() {
  installable=$1
  target_file=$2
  tmp_json=$(mktemp)
  trap 'rm -f "$tmp_json"' RETURN

  if ! firebreak_environment_nix_command print-dev-env --json "$installable" >"$tmp_json"; then
    echo "failed to resolve Firebreak devshell environment: $installable" >&2
    return 1
  fi

  DEVSHELL_JSON_PATH=$tmp_json "$(firebreak_environment_python)" - "$target_file" <<'PY'
import json
import os
import shlex
import sys
from pathlib import Path

deny_exact = {
    "HOME",
    "LOGNAME",
    "OLDPWD",
    "PWD",
    "SHELL",
    "SHLVL",
    "TERM",
    "TMPDIR",
    "USER",
    "XDG_RUNTIME_DIR",
}
deny_prefixes = ("FIREBREAK_",)

source_path = Path(os.environ["DEVSHELL_JSON_PATH"])
target_path = Path(sys.argv[1])
data = json.loads(source_path.read_text(encoding="utf-8"))
variables = data.get("variables") or {}
with target_path.open("a", encoding="utf-8") as handle:
    for key in sorted(variables):
        entry = variables[key]
        if key in deny_exact or any(key.startswith(prefix) for prefix in deny_prefixes):
            continue
        if entry.get("type") != "exported":
            continue
        value = entry.get("value")
        if not isinstance(value, str):
            continue
        handle.write(f'export {key}={shlex.quote(value)}\n')
PY
}

firebreak_environment_write_package_installable_overlay() {
  installable=$1
  target_file=$2
  output_paths=$(firebreak_environment_nix_command build --no-link --print-out-paths "$installable")
  if [ -z "$output_paths" ]; then
    echo "failed to resolve Firebreak package environment: $installable" >&2
    return 1
  fi

  while IFS= read -r output_path; do
    [ -n "$output_path" ] || continue
    if [ -d "$output_path/bin" ]; then
      printf 'if [ -d %s ]; then export PATH=%s:"$PATH"; fi\n' \
        "$(printf '%q' "$output_path/bin")" \
        "$(printf '%q' "$output_path/bin")" >>"$target_file"
    fi
  done <<EOF
$output_paths
EOF
}

firebreak_environment_write_manifest() {
  PROJECT_ROOT=$FIREBREAK_RESOLVED_PROJECT_ROOT \
    ENV_CACHE_DIR=$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR \
    ENV_FILE=$FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE \
    FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE=$FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE \
    FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY=$FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY \
    FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE=$FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE \
    FIREBREAK_RESOLVED_ENVIRONMENT_KIND=$FIREBREAK_RESOLVED_ENVIRONMENT_KIND \
    FIREBREAK_RESOLVED_ENVIRONMENT_MODE=$FIREBREAK_RESOLVED_ENVIRONMENT_MODE \
    FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON \
    FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY \
    FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON=$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON \
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_FLAKE_FILE=$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_FLAKE_FILE \
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH=$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH \
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED=$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED \
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE=$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE \
    FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION=$FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION \
    FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE=$FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE \
    MANIFEST_FILE=$FIREBREAK_RESOLVED_ENVIRONMENT_MANIFEST_FILE \
    "$(firebreak_environment_python)" - <<'PY'
import json
import os
from pathlib import Path

manifest = {
    "boot_base": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE", ""),
    "cache_dir": os.environ["ENV_CACHE_DIR"],
    "env_file": os.environ["ENV_FILE"],
    "identity": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY", ""),
    "installable": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE", ""),
    "kind": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_KIND", ""),
    "mode": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_MODE", ""),
    "package_exports_json": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON", "{}"),
    "package_identity": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY", ""),
    "package_paths_json": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON", "[]"),
    "project_flake_file": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_FLAKE_FILE", ""),
    "project_lock_hash": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH", ""),
    "project_nix_enabled": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED", "0") == "1",
    "project_nix_source": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE", "none"),
    "project_root": os.environ.get("PROJECT_ROOT", ""),
    "runtime_version": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION", ""),
    "source": os.environ.get("FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE", "none"),
}

manifest_path = Path(os.environ["MANIFEST_FILE"])
manifest_path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8")
PY
}

firebreak_materialize_environment_cache() {
  firebreak_environment_resolve_cache_paths

  mkdir -p "$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR"
  if [ -f "$FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE" ] && [ -f "$FIREBREAK_RESOLVED_ENVIRONMENT_MANIFEST_FILE" ]; then
    FIREBREAK_RESOLVED_ENVIRONMENT_REUSED=1
    FIREBREAK_RESOLVED_ENVIRONMENT_READY=1
    return 0
  fi

  tmp_env_file=$(mktemp "$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR/.environment.XXXXXX")
  {
    printf '# generated by Firebreak\n'
    printf 'export FIREBREAK_ENVIRONMENT_IDENTITY=%q\n' "$FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY"
  } >"$tmp_env_file"

  firebreak_environment_write_package_overlay "$tmp_env_file"

  case "$FIREBREAK_RESOLVED_ENVIRONMENT_KIND" in
    devshell)
      firebreak_environment_write_devshell_overlay "$FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE" "$tmp_env_file"
      ;;
    package)
      if [ -n "$FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE" ]; then
        firebreak_environment_write_package_installable_overlay "$FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE" "$tmp_env_file"
      fi
      ;;
    ""|none)
      :
      ;;
    *)
      echo "unsupported Firebreak environment kind: $FIREBREAK_RESOLVED_ENVIRONMENT_KIND" >&2
      rm -f "$tmp_env_file"
      return 1
      ;;
  esac

  mv -f "$tmp_env_file" "$FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE"
  firebreak_environment_write_manifest
  FIREBREAK_RESOLVED_ENVIRONMENT_READY=1
}

firebreak_resolve_environment() {
  firebreak_reset_environment_state
  firebreak_resolve_project_root

  FIREBREAK_RESOLVED_ENVIRONMENT_MODE=${FIREBREAK_ENVIRONMENT_MODE:-auto}
  if ! firebreak_environment_mode_allowed "$FIREBREAK_RESOLVED_ENVIRONMENT_MODE"; then
    echo "unsupported FIREBREAK_ENVIRONMENT_MODE: $FIREBREAK_RESOLVED_ENVIRONMENT_MODE" >&2
    return 1
  fi

  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED=${FIREBREAK_ENVIRONMENT_PROJECT_NIX_ENABLED:-0}
  FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_PATHS_JSON=${FIREBREAK_PACKAGE_ENVIRONMENT_PATHS_JSON:-[]}
  FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_EXPORTS_JSON=${FIREBREAK_PACKAGE_ENVIRONMENT_EXPORTS_JSON:-{}}
  FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY=${FIREBREAK_PACKAGE_IDENTITY:-}
  FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE=${FIREBREAK_BOOT_BASE:-interactive}
  FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION=${FIREBREAK_RUNTIME_GENERATION:-firebreak-cli}
  FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_FLAKE_FILE=$FIREBREAK_RESOLVED_PROJECT_ROOT/flake.nix

  project_lock_file=$FIREBREAK_RESOLVED_PROJECT_ROOT/flake.lock
  if project_lock_hash=$(firebreak_environment_hash_file "$project_lock_file" 2>/dev/null); then
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH=$project_lock_hash
  elif project_flake_hash=$(firebreak_environment_hash_file "$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_FLAKE_FILE" 2>/dev/null); then
    FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH=$project_flake_hash
  fi

  if [ "$FIREBREAK_RESOLVED_ENVIRONMENT_MODE" = "off" ]; then
    FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE="disabled"
    FIREBREAK_RESOLVED_ENVIRONMENT_KIND="none"
    firebreak_environment_resolve_cache_paths
    return 0
  fi

  if resolved_installable=$(firebreak_environment_resolve_explicit_installable); then
    FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE=$resolved_installable
    if [ "$FIREBREAK_RESOLVED_ENVIRONMENT_MODE" = "devshell" ] || [ "$FIREBREAK_RESOLVED_ENVIRONMENT_MODE" = "package" ]; then
      FIREBREAK_RESOLVED_ENVIRONMENT_KIND=$FIREBREAK_RESOLVED_ENVIRONMENT_MODE
    else
      FIREBREAK_RESOLVED_ENVIRONMENT_KIND=$(firebreak_environment_installable_kind "$resolved_installable")
    fi
    FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE="explicit"
    firebreak_environment_resolve_cache_paths
    return 0
  fi

  if IFS='|' read -r detected_kind detected_installable <<EOF
$(firebreak_environment_detect_project_installable || true)
EOF
  then
    if [ -n "${detected_installable:-}" ]; then
      FIREBREAK_RESOLVED_ENVIRONMENT_KIND=$detected_kind
      FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE=$detected_installable
      FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE="project-nix"
    fi
  fi

  if [ -z "$FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE" ] || [ "$FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE" = "none" ]; then
    FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE="package-only"
    FIREBREAK_RESOLVED_ENVIRONMENT_KIND="none"
  fi

  firebreak_environment_resolve_cache_paths
}

firebreak_environment_resolve_command() {
  environment_output=text

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json)
        environment_output=json
        shift
        ;;
      *)
        firebreak_environment_usage
        ;;
    esac
  done

  firebreak_load_project_config
  firebreak_resolve_environment
  firebreak_materialize_environment_cache

  if [ "$environment_output" = "json" ]; then
    cat <<EOF
{
  "project_root": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_PROJECT_ROOT")",
  "mode": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_MODE")",
  "source": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE")",
  "kind": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_KIND")",
  "installable": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE")",
  "identity": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY")",
  "cache_dir": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR")",
  "env_file": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE")",
  "manifest_file": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_MANIFEST_FILE")",
  "project_nix_enabled": $([ "$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED" = "1" ] && printf 'true' || printf 'false'),
  "project_nix_source": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE")",
  "project_lock_hash": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_LOCK_HASH")",
  "package_identity": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_PACKAGE_IDENTITY")",
  "boot_base": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_BOOT_BASE")",
  "runtime_version": "$(firebreak_environment_json_escape "$FIREBREAK_RESOLVED_ENVIRONMENT_RUNTIME_VERSION")",
  "reused": $([ "$FIREBREAK_RESOLVED_ENVIRONMENT_REUSED" = "1" ] && printf 'true' || printf 'false')
}
EOF
    return 0
  fi

  printf 'Firebreak Environment\n\n'
  printf '%-24s %s\n' "project_root" "$FIREBREAK_RESOLVED_PROJECT_ROOT"
  printf '%-24s %s\n' "mode" "$FIREBREAK_RESOLVED_ENVIRONMENT_MODE"
  printf '%-24s %s\n' "source" "$FIREBREAK_RESOLVED_ENVIRONMENT_SOURCE"
  printf '%-24s %s\n' "kind" "$FIREBREAK_RESOLVED_ENVIRONMENT_KIND"
  printf '%-24s %s\n' "installable" "${FIREBREAK_RESOLVED_ENVIRONMENT_INSTALLABLE:-none}"
  printf '%-24s %s\n' "identity" "$FIREBREAK_RESOLVED_ENVIRONMENT_IDENTITY"
  printf '%-24s %s\n' "cache_dir" "$FIREBREAK_RESOLVED_ENVIRONMENT_CACHE_DIR"
  printf '%-24s %s\n' "env_file" "$FIREBREAK_RESOLVED_ENVIRONMENT_ENV_FILE"
  printf '%-24s %s\n' "project_nix" "$FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_ENABLED ($FIREBREAK_RESOLVED_ENVIRONMENT_PROJECT_NIX_SOURCE)"
  printf '%-24s %s\n' "reused" "$FIREBREAK_RESOLVED_ENVIRONMENT_REUSED"
}
