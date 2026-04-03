@spec-015
Feature: Host-brokered orchestrated workers

  Scenario: external recipe declares process and firebreak worker kinds
    Given an external Firebreak orchestrator recipe
    When the maintainer defines orchestratable worker kinds
    Then the recipe can declare which backend each worker kind uses
    And the recipe can declare bounded concurrency for those worker kinds

  Scenario: process worker runs inside the orchestrator VM
    Given an orchestrator sandbox with a worker kind that uses the "process" backend
    When the orchestrator requests that worker kind
    Then Firebreak runs the worker inside the orchestrator VM
    And Firebreak keeps the shared guest runtime semantics for that worker

  Scenario: firebreak worker launches as a sibling worker VM
    Given an orchestrator sandbox with a worker kind that uses the "firebreak" backend
    When the orchestrator requests that worker kind
    Then Firebreak asks the host broker to launch a sibling worker VM
    And Firebreak does not require the guest to launch a nested VM directly

  Scenario: guest-visible worker lifecycle surface is backend-stable
    Given an orchestrator sandbox that can request more than one worker backend
    When the orchestrator lists, inspects, or stops workers
    Then Firebreak exposes the same lifecycle nouns across backends
    And Firebreak does not require raw host runner arguments in the guest-visible contract

  Scenario: orchestrator guest reaches the worker surface through a Firebreak bridge
    Given a local Firebreak orchestrator VM with worker bridging enabled
    When the guest runs "firebreak worker run"
    Then Firebreak forwards that request through the guest-visible bridge instead of exposing raw host runner internals
    And the guest can read the resulting worker metadata through the same surface

  Scenario: firebreak worker runtime state remains host-owned
    Given an orchestrated worker that uses the "firebreak" backend
    When Firebreak allocates the worker runtime state
    Then Firebreak keeps the worker instance directory, temporary root, and control socket under host ownership
    And Firebreak records reviewable worker metadata

  Scenario: orchestrated worker accesses the intended workspace
    Given an orchestrator sandbox that requests a worker against a project workspace
    When Firebreak launches that worker
    Then the worker resolves workspace access according to the orchestration contract
    And the worker acts on the intended project state
