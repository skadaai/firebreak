@spec-008
Feature: Single public local package with semantic VM mode override

  Scenario: The default public package starts the run mode
    Given the Firebreak local package "firebreak-codex"
    When the user launches that package without an entrypoint override
    Then the VM should start the default run mode

  Scenario: The same public package reaches the maintenance shell
    Given the Firebreak local package "firebreak-codex"
    When the user launches that package with "FIREBREAK_VM_MODE=shell"
    Then the VM should start the maintenance shell

  Scenario: Shell behavior is validated without a separate shell package
    Given the Firebreak smoke harness for a local package
    When the smoke test validates shell behavior
    Then it should use the same public package with a semantic shell override
