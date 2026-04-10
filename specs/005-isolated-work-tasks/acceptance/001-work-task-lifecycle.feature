@spec-005
Feature: Isolated workspaces

  Scenario: The autonomous operator creates an isolated workspace
    Given the primary Firebreak checkout is available
    When the autonomous operator creates a new workspace for branch "agent/spec-005"
    Then the system should create a dedicated git worktree for that workspace
    And the system should create isolated VM-state and artifact roots for that workspace
    And the system should persist workspace metadata for later validation and review

  Scenario: Two workspaces run in parallel without runner-state collisions
    Given two active autonomous workspaces with distinct identifiers
    When both workspaces run Firebreak VM validations at the same time
    Then the system should keep their runner volumes and control sockets isolated
    And neither workspace should overwrite the other's worktree or artifacts

  Scenario: Sequential work on one spec reuses one workspace
    Given an active workspace for spec "005-isolated-work-tasks"
    When the autonomous operator continues sequential work on that same spec
    Then the system should reuse the existing workspace
    And the system should not create an extra worktree for that continuation

  Scenario: A duplicate workspace request is deterministic
    Given an active workspace with identifier "workspace-123"
    When the autonomous operator requests another workspace with identifier "workspace-123"
    Then the system should deterministically reject or resume that workspace
    And the system should not create ambiguous duplicate state
