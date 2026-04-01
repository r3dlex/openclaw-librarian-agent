# Learnings

> Accumulated knowledge from the Librarian's operations.
> Update this file when you discover patterns, edge cases, or insights that should survive restarts.

## Format

Each entry should follow this structure:

```markdown
### <Short Title> (YYYY-MM-DD)

**Context**: What happened or what was observed.
**Insight**: What was learned.
**Action**: How this changes future behavior.
```

---

*No learnings recorded yet. This file will grow as the Librarian processes documents.*

## journalist_agent clock/tz issue (2026-03-25)
journalist_agent has been sending briefings dated 2026-03-30 and 2026-03-31 (4-6 days in future).
Also uses inconsistent weather locations: Stuttgart, Burgholzhof, Kaiserslautern.
Action: always file with the date the agent reports, add `note:` in front matter.
- journalist_agent clock skew resolved by 2026-03-31 — was 5-6 days ahead between Mar 25-30, now reporting correct dates.
