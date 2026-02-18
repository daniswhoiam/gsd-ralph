---
phase: test-phase
plan: 01
type: execute
wave: 1
---

<tasks>

<task type="auto">
  <name>Task 1: Single plan task</name>
  <files>src/component.sh</files>
  <action>Create the component file with basic structure.</action>
  <verify>File exists and is valid bash.</verify>
  <done>Component file created and passes ShellCheck.</done>
</task>

</tasks>
