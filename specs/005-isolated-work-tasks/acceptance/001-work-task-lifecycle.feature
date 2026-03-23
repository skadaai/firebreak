@spec-005
Feature: Isolated work tasks

  Scenario: The autonomous operator creates an isolated work task
    Given the primary Firebreak checkout is available
    When the autonomous operator creates a new work task for branch "agent/spec-005"
    Then the system should create a dedicated git worktree for that task
    And the system should create isolated VM-state and artifact roots for that task
    And the system should persist task metadata for later validation and review

  Scenario: Two work tasks run in parallel without runner-state collisions
    Given two active autonomous work tasks with distinct identifiers
    When both tasks run Firebreak VM validations at the same time
    Then the system should keep their runner volumes and control sockets isolated
    And neither task should overwrite the other's worktree or artifacts

  Scenario: A duplicate task request is deterministic
    Given an active work task with identifier "task-123"
    When the autonomous operator requests another work task with identifier "task-123"
    Then the system should deterministically reject or resume that task
    And the system should not create ambiguous duplicate state
