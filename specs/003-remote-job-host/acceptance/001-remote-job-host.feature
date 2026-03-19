@spec-003 @remote-host
Feature: Remote single-host Firebreak job runner

  Scenario: Run a prepared job on a remote Firebreak host
    Given the remote Firebreak host has available job capacity
    And a prepared workspace directory exists for job "job-123"
    And a prepared agent config directory exists for job "job-123"
    And an output directory exists for job "job-123"
    When the orchestrator starts job "job-123" with initial prompt "Inspect the repository and summarize the current architecture in ARCHITECTURE.md"
    Then the host shall launch exactly one Firebreak VM for the job
    And the host shall mount the prepared workspace into the guest using the cloud guest contract
    And the host shall start a new non-interactive Codex session for that prompt
    And the host shall persist stdout stderr and exit code under the job output directory
    And the host shall tear down transient runtime state after the job completes

  Scenario: Reject a job when host capacity is exhausted
    Given the remote Firebreak host job capacity is exhausted
    When the orchestrator starts a new job
    Then the host shall reject the job before launching a VM
    And the host shall return a diagnosable capacity error

  Scenario: Reject a job when required inputs are missing
    Given the remote Firebreak host has available job capacity
    And the required workspace directory for the job is missing
    When the orchestrator starts the job
    Then the host shall reject the job before launching a VM
    And the host shall return a diagnosable input error

  Scenario: Terminate a job when it exceeds the configured runtime limit
    Given the remote Firebreak host has available job capacity
    And a prepared workspace directory exists for job "job-124"
    And a prepared agent config directory exists for job "job-124"
    And an output directory exists for job "job-124"
    And the job runtime limit is configured for the host
    When the orchestrator starts job "job-124" with an initial prompt that exceeds the runtime limit
    Then the host shall terminate the Firebreak VM for the job
    And the host shall return a diagnosable timeout result
    And the host shall tear down transient runtime state after termination
