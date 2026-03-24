@spec-013
Feature: Apple Silicon local support

  Scenario: Local launch on an Apple Silicon Mac
    Given an operator is on an `aarch64-darwin` host
    When the operator runs `nix run .#firebreak-codex`
    Then Firebreak evaluates a local Apple Silicon host package
    And Firebreak launches an `aarch64-linux` guest through a `vfkit`-based local runtime

  Scenario: Shell mode on an Apple Silicon Mac
    Given an operator is on an `aarch64-darwin` host
    When the operator runs `FIREBREAK_VM_MODE=shell nix run .#firebreak-codex`
    Then Firebreak reaches the maintenance shell through the Apple Silicon local runtime

  Scenario: Unsupported Intel Mac host
    Given an operator is on an `x86_64-darwin` host
    When the operator attempts to launch a local Firebreak workload
    Then Firebreak fails clearly because Intel Mac support is out of scope

  Scenario: Unsupported cloud path on macOS
    Given an operator is on a macOS host
    When the operator attempts to use a cloud execution path
    Then Firebreak fails clearly because cloud macOS support is out of scope
