set -eu

repo_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/flake.nix" ]; then
  echo "run this smoke test from inside the codex-vm repository" >&2
  exit 1
fi

host_uid=$(id -u)
host_gid=$(id -g)
timeout_seconds=${CODEX_VM_SMOKE_TIMEOUT:-180}

cd "$repo_root"

timeout --foreground "$timeout_seconds" expect - "$repo_root" "$host_uid" "$host_gid" <<'EOF'
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
set timeout 60
match_max 100000

spawn env CODEX_CONFIG=workspace nix --accept-flake-config --extra-experimental-features {nix-command flakes} run .#codex-vm

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

set codex_config_dir [run_and_capture {printf '__SMOKE_CONFIG_DIR__%s\n' "$CODEX_CONFIG_DIR"} {__SMOKE_CONFIG_DIR__(.+)\r\n} "Codex config directory"]
if {$codex_config_dir ne "$repo_root/.codex"} {
  fail "unexpected Codex config directory: $codex_config_dir"
}

run_and_assert {test -f flake.nix && echo __SMOKE_FLAKE__ok} {__SMOKE_FLAKE__ok\r\n} "workspace contents"
run_and_assert {codex --version | sed -n '1s/^/__SMOKE_CODEX__/p'} {__SMOKE_CODEX__.+\r\n} "Codex CLI"

send -- "sudo poweroff\r"
expect {
  eof { exit 0 }
  timeout { fail "timed out waiting for codex-vm to power off" }
}
EOF

printf '%s\n' "codex-vm smoke test passed"
