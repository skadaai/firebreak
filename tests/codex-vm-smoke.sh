set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the codex-vm repository" >&2
  exit 1
fi

host_uid=$(id -u)
host_gid=$(id -g)
timeout_seconds=${CODEX_VM_SMOKE_TIMEOUT:-180}
host_config_dir=$(mktemp -d)

trap 'rm -rf "$host_config_dir"' EXIT INT TERM

printf '%s\n' "host-smoke-marker" > "$host_config_dir/marker.txt"

cd "$repo_root"

run_scenario() {
  package_name=$1
  mode=$2
  expected_config_dir=$3
  expect_agent_entry=${4-0}
  host_config_path=${5-}
  host_marker_name=${6-}

  timeout --foreground "$timeout_seconds" expect - \
    "$repo_root" \
    "$host_uid" \
    "$host_gid" \
    "$package_name" \
    "$mode" \
    "$expected_config_dir" \
    "$expect_agent_entry" \
    "$host_config_path" \
    "$host_marker_name" <<'EOF'
proc fail {message} {
  puts stderr $message
  catch {send -- "sudo poweroff\r"}
  exit 1
}

proc expect_prompt {} {
  expect {
    -re {\[dev@codex-vm:[^]]+\]\$ $} { return }
    timeout { fail "timed out waiting for the codex-vm shell prompt" }
    eof { fail "codex-vm exited before the smoke test completed" }
  }
}

proc run_and_capture {command pattern description} {
  send -- "$command\r"
  expect {
    -re $pattern {
      set value $expect_out(1,string)
    }
    timeout { fail "timed out while checking $description" }
    eof { fail "codex-vm exited while checking $description" }
  }
  expect_prompt
  return $value
}

proc run_and_assert {command pattern description} {
  send -- "$command\r"
  expect {
    -re $pattern { }
    timeout { fail "timed out while checking $description" }
    eof { fail "codex-vm exited while checking $description" }
  }
  expect_prompt
}

set repo_root [lindex $argv 0]
set host_uid [lindex $argv 1]
set host_gid [lindex $argv 2]
set package_name [lindex $argv 3]
set mode [lindex $argv 4]
set expected_config_dir [lindex $argv 5]
set expect_agent_entry [lindex $argv 6]
set host_config_dir [lindex $argv 7]
set host_marker_name [lindex $argv 8]
set timeout 60
match_max 100000

set spawn_cmd [list env AGENT_CONFIG=$mode]
if {$host_config_dir ne ""} {
  lappend spawn_cmd AGENT_CONFIG_HOST_PATH=$host_config_dir
}
lappend spawn_cmd nix --accept-flake-config --extra-experimental-features {nix-command flakes} run .#$package_name
spawn -noecho {*}$spawn_cmd

if {$expect_agent_entry eq "1"} {
  expect {
    -re {__AGENT_ENTRY__codex\r\n} { }
    timeout { fail "timed out waiting for the default agent entry marker" }
    eof { fail "codex-vm exited before the default agent entry marker appeared" }
  }
  send -- "\003"
}

expect_prompt

set guest_pwd [run_and_capture {printf '__SMOKE_PWD__%s\n' "$PWD"} {__SMOKE_PWD__(.+)\r\n} "guest working directory"]
if {$guest_pwd ne $repo_root} {
  fail "unexpected guest working directory: $guest_pwd"
}

set guest_ids [run_and_capture {printf '__SMOKE_IDS__%s:%s\n' "$(id -u)" "$(id -g)"} {__SMOKE_IDS__([0-9]+:[0-9]+)\r\n} "guest uid/gid"]
if {$guest_ids ne "$host_uid:$host_gid"} {
  fail "unexpected guest uid/gid: $guest_ids"
}

set workspace_owner [run_and_capture {printf '__SMOKE_OWNER__%s\n' "$(stat -c '%u:%g' .)"} {__SMOKE_OWNER__([0-9]+:[0-9]+)\r\n} "workspace ownership"]
if {$workspace_owner ne "$host_uid:$host_gid"} {
  fail "unexpected workspace ownership: $workspace_owner"
}

set codex_config_dir [run_and_capture {printf '__SMOKE_CONFIG_DIR__%s\n' "$AGENT_CONFIG_DIR"} {__SMOKE_CONFIG_DIR__(.+)\r\n} "agent config directory"]
if {$codex_config_dir ne $expected_config_dir} {
  fail "unexpected Codex config directory: $codex_config_dir"
}

run_and_assert {test -f flake.nix && echo __SMOKE_FLAKE__ok} {__SMOKE_FLAKE__ok\r\n} "workspace contents"
if {$mode ne "workspace"} {
  run_and_assert {test -d "$AGENT_CONFIG_DIR" && test -w "$AGENT_CONFIG_DIR" && echo __SMOKE_CONFIG_DIR__ok} {__SMOKE_CONFIG_DIR__ok\r\n} "agent config directory usability"
}
if {$mode eq "host"} {
  run_and_assert "test -f \"$AGENT_CONFIG_DIR/$host_marker_name\" && echo __SMOKE_HOST_CONFIG__ok" {__SMOKE_HOST_CONFIG__ok\r\n} "host agent config mount"
}
run_and_assert {codex --version | sed -n '1s/^/__SMOKE_CODEX__/p'} {__SMOKE_CODEX__.+\r\n} "Codex CLI"

send -- "sudo poweroff\r"
expect {
  eof { exit 0 }
  timeout { fail "timed out waiting for codex-vm to power off" }
}
EOF
}

run_scenario codex-vm workspace "$repo_root/.codex" 1
run_scenario codex-vm-shell workspace "$repo_root/.codex"
run_scenario codex-vm-shell vm "/var/lib/dev/.codex"
run_scenario codex-vm-shell host "/run/agent-config-host" 0 "$host_config_dir" "marker.txt"

printf '%s\n' "codex-vm smoke test passed"
