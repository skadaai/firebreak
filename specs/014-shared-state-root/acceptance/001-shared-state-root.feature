@spec-014
Feature: Shared state root

  Scenario: generic selector defaults both wrappers
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the sandbox enables the shared state-root contract
    And the operator sets "FIREBREAK_STATE_MODE=workspace"
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak resolves the Codex state directory under the workspace contract
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak resolves the Claude Code state directory under the workspace contract

  Scenario: tool-specific selectors override the generic selector
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the sandbox enables the shared state-root contract
    And the operator sets "FIREBREAK_STATE_MODE=vm"
    And the operator sets "CODEX_STATE_MODE=host"
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak resolves Codex state from the host-backed shared state root
    And the generic selector does not override that Codex-specific choice
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak resolves Claude Code state from the generic `vm` selector

  Scenario: host mode resolves stable per-tool subdirectories
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the sandbox enables the shared state-root contract
    And the operator enables `host` mode for both tools
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak resolves a Codex-specific subdirectory within the mounted host state root
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak resolves a Claude-specific subdirectory within the mounted host state root
    And Firebreak does not reuse the same leaf directory for both tools

  Scenario: wrappers translate Firebreak resolution into tool-native env vars
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the operator sets "FIREBREAK_STATE_MODE=workspace"
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak exports the resolved directory through Codex-native config env vars
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak exports the resolved directory through Claude-native config env vars
