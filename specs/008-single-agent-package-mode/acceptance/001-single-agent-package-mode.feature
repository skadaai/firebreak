@spec-008
Feature: Single public local agent package with semantic mode override

  Scenario: The default public agent package starts the agent mode
    Given the Firebreak local agent package "firebreak-codex"
    When the user launches that package without an entrypoint override
    Then the VM should start the default agent mode

  Scenario: The same public package reaches the maintenance shell
    Given the Firebreak local agent package "firebreak-codex"
    When the user launches that package with "AGENT_VM_ENTRYPOINT=shell"
    Then the VM should start the maintenance shell

  Scenario: Shell behavior is validated without a separate shell package
    Given the Firebreak smoke harness for a local agent package
    When the smoke test validates shell behavior
    Then it should use the same public agent package with a semantic shell override
