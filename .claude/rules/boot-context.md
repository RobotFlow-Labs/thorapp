# Boot Context — MANDATORY on every session

## Rule: Read project state BEFORE doing anything

On EVERY session start, read these files in order:
1. `NEXT_STEPS.md` — current status, blockers, what's done
2. `CLAUDE.md` — project overview and architecture
3. `M0_ARCHITECTURE_SPEC.md` — architecture decisions and contracts
4. `BUILD_ROADMAP.md` — milestones and dependencies
5. `git log --oneline -10` — recent commits from this and other agents

Only AFTER reading all of these should you respond to the user or start working.

If `NEXT_STEPS.md` doesn't exist, create it.
If `BUILD_ROADMAP.md` has a milestone table, identify the current milestone.
If git log shows recent commits, understand what was already built.

**Why:** Multiple agents work on this project across sessions. Without reading state first, agents duplicate work, miss blockers, and lose context. This rule ensures every agent starts informed.
