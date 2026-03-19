@spec-002 @cloud-profile
Feature: Cloud guest execution profile

  Scenario: Run a one-shot agent job against a prepared workspace
    Given the cloud execution profile is enabled
    And a prepared workspace input is available to the guest
    And a prepared agent config input is available to the guest
    And the selected agent runtime supports non-interactive prompt-driven execution
    And the requested initial prompt is "Inspect the repository and print a short architecture summary to standard output"
    When the guest boots for the job
    Then the guest shall use the fixed cloud workspace path
    And the guest shall not require dynamic host cwd metadata
    And the guest shall not rewrite the development user uid or gid from host metadata
    And the guest shall start a new non-interactive agent session for that prompt
    And stdout stderr and exit code shall be persisted to host-visible output paths
    And the guest shall terminate after persisting outputs

  Scenario: Fail fast when the required workspace input is missing
    Given the cloud execution profile is enabled
    And the required workspace input is absent
    When the guest boots for the job
    Then the guest shall return a non-zero result
    And the guest shall emit a diagnosable error message
    And the guest shall not fall back to an interactive shell
