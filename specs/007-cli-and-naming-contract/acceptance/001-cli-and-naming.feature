@spec-007
Feature: CLI and naming contract

  Scenario: Development workflow commands live in the separate dev-flow CLI
    Given the Firebreak CLI is installed
    When an operator asks for command help
    Then the top-level command list should expose only the human-facing Firebreak surface
    And the separate dev-flow CLI should route workspace, validate, and loop operations

  Scenario: The host-side isolated checkout concept is named workspace
    Given the host-side isolated work contract is available
    When the operator creates and closes one isolated work attempt
    Then the CLI and machine-readable outputs should use workspace and attempt terminology instead of blurred task/session terminology

  Scenario: Workflow and test packages follow the naming grammar
    Given the Firebreak flake exports human, workflow, and test packages
    When the operator inspects the exported packages and checks
    Then human-facing packages should remain under intuitive top-level names
    And workflow packages should use the dev-flow prefix
    And smoke tests should use the firebreak-test-smoke prefix
