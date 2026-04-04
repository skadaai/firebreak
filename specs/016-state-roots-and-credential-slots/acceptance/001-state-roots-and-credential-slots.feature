@spec-016
Feature: State roots and credential slots

  Scenario: workspace mode keeps native project config in the mounted workspace
    Given a project that already contains a tool-native project config folder
    When the operator runs that tool through Firebreak in workspace mode
    Then the tool continues reading its project config from the mounted workspace
    And Firebreak does not replace that native project config folder with a Firebreak-owned overlay

  Scenario: workspace mode isolates runtime state per project
    Given two different projects that run the same packaged tool through Firebreak
    When both projects use workspace mode
    Then each project receives an isolated runtime state root
    And that isolation does not depend on replacing the tool's native project config folder

  Scenario: a package opts into a file-based credential adapter
    Given a package that declares a file-based credential adapter
    And the operator selects a named credential slot
    When Firebreak launches that package
    Then Firebreak materializes the selected slot at the file path the tool naturally expects

  Scenario: a native login flow writes directly into a selected slot
    Given a package that declares a native login command and a file-based credential adapter
    And the operator selects a named credential slot
    When Firebreak runs the package's native login flow through the credential adapter
    Then the resulting credential artifact lands directly in the selected slot
    And Firebreak does not require a post-login capture step as the primary path

  Scenario: a package opts into env-driven credentials
    Given a package that declares an env-based credential adapter
    And the selected slot contains a credential value for that adapter
    When Firebreak launches that package
    Then Firebreak exports the corresponding env var expected by the tool

  Scenario: a package opts into helper-driven credentials
    Given a package that declares a helper-driven credential adapter
    And the selected slot contains the material expected by that helper
    When Firebreak launches that package
    Then Firebreak materializes a helper command or script that the tool can call
    And that helper resolves credentials from the selected slot

  Scenario: a multi-tool sandbox uses a default slot plus a per-tool override
    Given a sandbox that exposes more than one packaged tool
    And the operator selects one default credential slot plus an override for one tool
    When Firebreak launches that sandbox
    Then the overridden tool resolves credentials from its override slot
    And the other tool resolves credentials from the default slot
