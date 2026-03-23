@spec-007
Feature: CLI and naming contract

  Scenario: Internal plumbing lives under the internal subtree
    Given the Firebreak CLI is installed
    When an operator asks for command help
    Then the top-level command list should expose the internal subtree instead of surfacing task, validate, or loop plumbing directly
    And the internal subtree should route task, validate, and loop operations

  Scenario: The host-side isolated workspace concept is named task
    Given the host-side isolated work contract is available
    When the operator creates and closes one isolated work attempt
    Then the CLI and machine-readable outputs should use task terminology instead of session terminology

  Scenario: Internal and test packages follow the naming grammar
    Given the Firebreak flake exports human, internal, and test packages
    When the operator inspects the exported packages and checks
    Then human-facing packages should remain under intuitive top-level names
    And internal plumbing packages should use the firebreak-internal prefix
    And smoke tests should use the firebreak-test-smoke prefix
