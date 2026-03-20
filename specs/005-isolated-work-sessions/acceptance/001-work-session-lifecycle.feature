@spec-005
Feature: Isolated work sessions

  Scenario: The autonomous operator creates an isolated work session
    Given the primary Firebreak checkout is available
    When the autonomous operator creates a new work session for branch "agent/spec-005"
    Then the system should create a dedicated git worktree for that session
    And the system should create isolated VM-state and artifact roots for that session
    And the system should persist session metadata for later validation and review

  Scenario: Two work sessions run in parallel without runner-state collisions
    Given two active autonomous work sessions with distinct identifiers
    When both sessions run Firebreak VM validations at the same time
    Then the system should keep their runner volumes and control sockets isolated
    And neither session should overwrite the other's worktree or artifacts

  Scenario: A duplicate session request is deterministic
    Given an active work session with identifier "session-123"
    When the autonomous operator requests another work session with identifier "session-123"
    Then the system should deterministically reject or resume that session
    And the system should not create ambiguous duplicate state
