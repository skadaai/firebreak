@spec-009
Feature: Firebreak project config and diagnostics

  Scenario: bootstrap a Firebreak-native project defaults file
    Given a project without a .firebreak.env file
    When the operator runs "firebreak init"
    Then Firebreak writes a ".firebreak.env" file
    And the file uses "KEY=VALUE" entries
    And the file contains only Firebreak-native public settings
    And the file does not use a legacy sandbox file name

  Scenario: process environment overrides the project defaults file
    Given a project with ".firebreak.env" that sets a supported public Firebreak key
    And the operator sets the same key in the process environment to a different value
    When the operator runs a Firebreak command that resolves that key
    Then Firebreak uses the process environment value

  Scenario: unsupported internal keys are excluded from the project defaults contract
    Given a project with ".firebreak.env" that sets an internal plumbing key
    When Firebreak loads the project defaults file
    Then Firebreak ignores that key as part of the public config contract
    And "firebreak doctor" can report that the key is unsupported

  Scenario: tool-specific selectors override generic defaults
    Given a project with ".firebreak.env" that sets both a generic agent selector and a Codex-specific selector
    When the operator resolves local Codex launch settings
    Then Firebreak uses the Codex-specific selector
    And the generic selector remains available as the fallback for other workloads

  Scenario: doctor explains the resolved Firebreak state before launch
    Given a project with or without ".firebreak.env"
    When the operator runs "firebreak doctor"
    Then Firebreak reports the resolved project root
    And Firebreak reports the resolved project config source
    And Firebreak reports the local mode selector state
    And Firebreak reports the resolved tool state
    And Firebreak reports whether KVM is readable and writable
    And Firebreak reports whether current working directory is compatible

  Scenario: json doctor output is machine-readable
    Given a project with Firebreak available
    When the operator runs "firebreak doctor --json"
    Then Firebreak emits machine-readable diagnostics
    And Firebreak includes cwd-compatibility diagnostics in the JSON output

  Scenario: verbose doctor output includes expanded diagnostics
    Given a project with Firebreak available
    When the operator runs "firebreak doctor --verbose"
    Then Firebreak emits the expanded human-readable diagnostics fields

  Scenario: verbose json doctor output keeps machine-readable fields
    Given a project with Firebreak available
    When the operator runs "firebreak doctor --verbose --json"
    Then Firebreak emits machine-readable diagnostics
    And Firebreak includes the same verbose fields in JSON form
