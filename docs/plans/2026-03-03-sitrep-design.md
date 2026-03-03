# /sitrep — Situation Report Skill

## Goal

A slash command that gives an intelligent status update when picking up work mid-context in any git repository. Brief by default, detailed on demand.

## Two Modes

### Brief Mode (`/sitrep`)

Single-agent sequential scan. Gathers surface-level information from all sources without deep file reading. Produces a 3-5 line summary. Ends with an offer to expand ("Want the full report? Say yes or run `/sitrep --full`.").

**Sources checked (shallow):**
- `git status`, `git log --oneline -5`, `git branch`
- Claude TaskList (if any active tasks)
- `ls docs/plans/` (names + dates only, no content reading)
- `gh pr list --state open --limit 5`
- `gh issue list --state open --limit 5`
- Auto-memory files for the current project

### Full Mode (`/sitrep --full`)

Spawns 4 parallel Explore subagents, each investigating a domain. Collects results and synthesizes a structured markdown report.

**Parallel agents:**

| Agent | Domain | What it checks |
|-------|--------|----------------|
| git-scout | Git & branch state | Current branch, recent commits, uncommitted changes, divergence from main, stale branches |
| plan-analyst | Plan docs & tasks | `docs/plans/*.md` contents, cross-references code to assess implementation status, Claude TaskList state |
| github-intel | GitHub PRs & issues | Open PRs with CI status and review state, open issues, recently merged PRs via `gh` CLI |
| memory-recall | Auto-memory & context | Claude auto-memory files for the project, prior session notes, saved context |

**Structured output sections:**
1. Current Status — branch, last activity, uncommitted changes
2. Task Progress — what's done, what's pending, blockers
3. Plan Progress — per-plan breakdown with implementation status (verified against code)
4. GitHub State — PRs, issues, CI
5. Suggested Next Steps — prioritized list of what to do next

## File Structure

```
skills/
  sitrep/
    SKILL.md              # Main skill prompt (brief + full mode logic)
commands/
  sitrep.md               # /sitrep slash command entry point
```

## Design Decisions

- Brief mode does no deep file reading — surface checks only for speed.
- Full mode agents are Explore type (read-only) — this skill never writes or edits.
- Plan status in full mode reads actual code to verify implementation state.
- Works in any git repo, not just a-team projects.
- Ambiguous plan items are just noted in brief mode; full mode investigates and makes a judgment.
