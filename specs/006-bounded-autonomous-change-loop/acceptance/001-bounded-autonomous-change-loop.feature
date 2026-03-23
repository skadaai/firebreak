@spec-006
Feature: Bounded autonomous change loop

  Scenario: An autonomous change succeeds within the defined loop
    Given a tracked Firebreak spec and an isolated work task
    And the required validation suites are runnable on the host
    When the autonomous operator completes a bounded implementation slice
    Then the system should record the slice plan before the change
    And the system should run the required validation suites
    And the system should perform a review pass before commit
    And the system should persist an audit trail for the resulting disposition

  Scenario: Missing validation capability blocks the change
    Given a tracked Firebreak spec and an isolated work task
    And the required validation suites are not runnable on the host
    When the autonomous operator reaches the validation stage
    Then the system should stop with a blocked result
    And the system should not claim the change is complete
    And the system should preserve evidence explaining the blocked state

  Scenario: A policy violation stops the change before action
    Given a tracked Firebreak spec and an isolated work task
    And the attempted action exceeds configured writable scope or runtime policy
    When the autonomous operator prepares to take that action
    Then the system should stop before performing the action
    And the system should record the policy reason in the audit trail
