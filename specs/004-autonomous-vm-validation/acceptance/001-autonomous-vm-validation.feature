@spec-004
Feature: Autonomous VM validation

  Scenario: A runnable host executes a named Firebreak VM suite
    Given a host that satisfies the "local-smoke" suite capabilities
    When the autonomous operator runs the "local-smoke" validation suite
    Then the system should report a passing suite result
    And the system should persist a machine-readable summary for that run
    And the system should preserve suite logs and evidence paths for later review

  Scenario: A blocked host does not pretend to have run the suite
    Given a host that does not satisfy the "local-smoke" suite capabilities
    When the autonomous operator runs the "local-smoke" validation suite
    Then the system should report a blocked suite result
    And the system should explain which required host capability is missing
    And the system should not report a guest-regression failure for that run
