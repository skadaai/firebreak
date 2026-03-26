@spec-014
Feature: Shared agent config root

  Scenario: generic selector defaults both wrappers
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the sandbox enables the shared agent config-root contract
    And the operator sets "AGENT_CONFIG=workspace"
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak resolves the Codex config directory under the workspace contract
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak resolves the Claude Code config directory under the workspace contract

  Scenario: agent-specific selectors override the generic selector
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the operator sets "AGENT_CONFIG=vm"
    And the operator sets "CODEX_CONFIG=host"
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak resolves Codex config from the host-backed shared config root
    And the generic selector does not override that Codex-specific choice
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak resolves Claude Code config from the generic `vm` selector

  Scenario: host mode resolves stable per-agent subdirectories
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    And the sandbox enables the shared agent config-root contract
    And the operator enables `host` mode for both tools
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak resolves a Codex-specific subdirectory within the mounted host config root
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak resolves a Claude-specific subdirectory within the mounted host config root
    And Firebreak does not reuse the same leaf directory for both tools

  Scenario: wrappers translate Firebreak resolution into agent-native env vars
    Given a Firebreak sandbox that exposes both Codex and Claude Code
    When the operator launches the Firebreak Codex wrapper
    Then Firebreak exports the resolved directory through Codex-native config env vars
    When the operator launches the Firebreak Claude Code wrapper
    Then Firebreak exports the resolved directory through Claude-native config env vars
