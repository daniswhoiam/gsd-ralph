---
phase: quick
plan: 1
subsystem: docs
tags: [autopilot, ralph, auto-advance, skill-rules]

# Dependency graph
requires: []
provides:
  - "SKILL.md Rule 6 distinguishing --ralph from --auto scope boundary"
affects: [gsd-ralph-autopilot]

# Tech tracking
tech-stack:
  added: []
  patterns: ["scope boundary documentation for flag disambiguation"]

key-files:
  created: []
  modified:
    - ".claude/skills/gsd-ralph-autopilot/SKILL.md"

key-decisions:
  - "Followed existing Rule 1-5 naming convention and imperative style for Rule 6"

patterns-established:
  - "Scope boundary documentation pattern: explicit positive (what X does) + negative (what X does NOT do) + boundary rule"

requirements-completed: []

# Metrics
duration: 1min
completed: 2026-03-10
---

# Quick Task 1: Document Ralph vs Auto-Advance Distinction Summary

**Added Rule 6 to SKILL.md: explicit scope boundary distinguishing --ralph (within-workflow autonomy) from --auto (cross-workflow chaining)**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-10T19:51:05Z
- **Completed:** 2026-03-10T19:51:57Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added Rule 6: Scope Boundary -- Ralph vs Auto-Advance to SKILL.md
- Documented that --ralph authorizes within-workflow autonomy only (checkpoints, decisions, human-action skips)
- Documented that --ralph does NOT imply --auto, does NOT permit cross-workflow chaining
- Clarified independent operation when both --ralph and --auto are present
- Updated frontmatter description with scope boundary note

## Task Commits

Each task was committed atomically:

1. **Task 1: Add scope boundary rule to SKILL.md** - `c3b6979` (docs)

## Files Created/Modified
- `.claude/skills/gsd-ralph-autopilot/SKILL.md` - Added Rule 6 scope boundary section and updated frontmatter description

## Decisions Made
- Followed existing Rule 1-5 naming convention and imperative style for consistency
- Structured Rule 6 with three subsections (authorizes / does NOT authorize / boundary rule) for unambiguous reading

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SKILL.md now prevents orchestrators from misinterpreting --ralph as --auto
- No follow-up work needed

## Self-Check: PASSED

- FOUND: .claude/skills/gsd-ralph-autopilot/SKILL.md
- FOUND: 1-SUMMARY.md
- FOUND: commit c3b6979

---
*Quick Task: 1-document-ralph-vs-auto-flag-distinction*
*Completed: 2026-03-10*
