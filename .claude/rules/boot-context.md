# Boot Context — MANDATORY on every session

## Rule: Read project state BEFORE doing anything

On EVERY session start, read these files in order:
1. `NEXT_STEPS.md` — current status, blockers, what's done
2. `CLAUDE.md` — project overview, architecture, AND the rules/skills table
3. `.claude/rules/thorctl-skill.md` — full command reference + 50 endpoint map
4. `git log --oneline -10` — recent commits from this and other agents

Only AFTER reading all of these should you respond to the user or start working.

## Rule: Verify device state with thorctl

Before any device-related work:
```bash
make docker-up           # Ensure sims running
thorctl health 8470      # Check Thor sim
thorctl health 8471      # Check Orin sim
```

After any agent or view changes:
```bash
swift build              # 0 errors, 0 warnings
swift test               # 71+ tests pass
docker compose down && docker compose build --no-cache && docker compose up -d
sleep 5 && thorctl health 8470
```

If `NEXT_STEPS.md` doesn't exist, create it.
If git log shows recent commits, understand what was already built.

**Why:** Multiple agents work on this project across sessions. Without reading state first, agents duplicate work, miss blockers, and lose context. thorctl is the ground truth for device state.
