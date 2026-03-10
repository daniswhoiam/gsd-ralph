# Requirements: gsd-ralph

**Defined:** 2026-03-10
**Core Value:** Add `--ralph` to any GSD command and walk away — Ralph drives, GSD works, code ships.

## v2.1 Requirements

Requirements for Easy Install milestone. Each maps to roadmap phases.

### Installation

- [ ] **INST-01**: User can install gsd-ralph into any repo with a single terminal command
- [ ] **INST-02**: Installer checks for GSD framework and displays version guidance if missing
- [ ] **INST-03**: Installer checks for jq, git, and bash >= 3.2 with actionable fix instructions
- [ ] **INST-04**: Re-running the installer is safe — identical files are skipped, no data loss
- [ ] **INST-05**: Installer adds ralph config section to .planning/config.json without overwriting existing settings
- [ ] **INST-06**: Installer copies all Ralph components (scripts, skills, commands) to target repo
- [ ] **INST-07**: Post-install verification confirms all files exist and are executable
- [ ] **INST-08**: Installer displays clear output with next-step guidance after completion

### Portability

- [ ] **PORT-01**: Ralph scripts work from both `scripts/` (dev repo) and `scripts/ralph/` (installed repo)
- [ ] **PORT-02**: All script-to-script references use configurable paths, not hardcoded locations
- [ ] **PORT-03**: Existing 315 tests pass after portability refactor

## Future Requirements

Deferred to v2.2+. Tracked but not in current roadmap.

### Lifecycle

- **LIFE-01**: User can uninstall gsd-ralph cleanly via manifest-based removal
- **LIFE-02**: User can upgrade gsd-ralph in-place preserving user config
- **LIFE-03**: Version tracking in `.ralph/.version` enables upgrade detection

### Distribution

- **DIST-01**: gsd-ralph available as Claude Code plugin (when namespacing supports custom paths)
- **DIST-02**: gsd-ralph listed in Claude Code marketplace

## Out of Scope

| Feature | Reason |
|---------|--------|
| Claude Code plugin packaging | Plugin namespacing breaks `/gsd:ralph` command — produces `/gsd-ralph:ralph` instead |
| npm/npx package | gsd-ralph is pure Bash; npm adds conceptual mismatch and unnecessary dependency |
| Homebrew formula | Overkill for a Claude Code-specific tool |
| curl-pipe-bash pattern | Security concerns; download-then-execute is safer |
| Auto-update mechanism | Explicit upgrade is safer for autonomous execution tool |
| Multi-repo batch installer | Single-repo focus for v2.1 |
| settings.local.json modification at install time | Launcher handles hooks dynamically at runtime — static install would interfere |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | Phase 15 | Pending |
| INST-02 | Phase 15 | Pending |
| INST-03 | Phase 15 | Pending |
| INST-04 | Phase 15 | Pending |
| INST-05 | Phase 15 | Pending |
| INST-06 | Phase 15 | Pending |
| INST-07 | Phase 15 | Pending |
| INST-08 | Phase 15 | Pending |
| PORT-01 | Phase 14 | Pending |
| PORT-02 | Phase 14 | Pending |
| PORT-03 | Phase 14 | Pending |

**Coverage:**
- v2.1 requirements: 11 total
- Mapped to phases: 11
- Unmapped: 0

---
*Requirements defined: 2026-03-10*
*Last updated: 2026-03-10 after roadmap creation*
