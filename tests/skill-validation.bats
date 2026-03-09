#!/usr/bin/env bats
# tests/skill-validation.bats -- Validates SKILL.md content and structure

setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"
    SKILL_FILE="$REAL_PROJECT_ROOT/.claude/skills/gsd-ralph-autopilot/SKILL.md"
}

teardown() {
    _common_teardown
}

@test "SKILL.md file exists at .claude/skills/gsd-ralph-autopilot/SKILL.md" {
    assert_file_exists "$SKILL_FILE"
}

@test "SKILL.md frontmatter contains name: gsd-ralph-autopilot" {
    run grep -E '^name:\s*gsd-ralph-autopilot' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md frontmatter contains user-invocable: false" {
    run grep -E '^user-invocable:\s*false' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md body contains AskUserQuestion rule (never call it)" {
    run grep -i 'AskUserQuestion' "$SKILL_FILE"
    assert_success
    # Verify it says NEVER
    run grep -i 'NEVER.*AskUserQuestion\|AskUserQuestion.*NEVER' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md body contains first option decision strategy" {
    run grep -i 'first option' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md body contains checkpoint auto-approve with git commit" {
    run grep -i 'auto-approve\|auto.approve' "$SKILL_FILE"
    assert_success
    run grep -i 'git commit\|commit.*checkpoint\|checkpoint.*commit' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md body contains skip human-action steps rule" {
    run grep -i 'skip.*human.action\|human.action.*skip' "$SKILL_FILE"
    assert_success
    run grep -i 'SKIPPED (autonomous mode)' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md body contains clean exit rule (no invented work)" {
    run grep -i 'clean.*exit\|exit.*clean' "$SKILL_FILE"
    assert_success
    run grep -i 'invent.*work\|additional work\|invented' "$SKILL_FILE"
    assert_success
}

@test "SKILL.md does NOT reference specific GSD file formats or phase structures" {
    # Anti-pattern: SKILL.md should contain behavior rules only
    # It should NOT reference specific file parsing patterns
    run grep -iE 'parse.*ROADMAP|ROADMAP.*parse|parse.*frontmatter' "$SKILL_FILE"
    assert_failure
    run grep -iE 'phase [0-9]+ of [0-9]+|Plan: [0-9]+ of' "$SKILL_FILE"
    assert_failure
}
