---
name: team-driven-development
description: Use when executing implementation plans with a parallel agent team - spawns teammate agents that each own tasks end-to-end including PRs and CI, with a PR shepherd for merge ordering. Alternative to subagent-driven-development and executing-plans.
---

# Team-Driven Development

Orchestrate a team of Claude Code agents to execute an implementation plan in parallel. Each teammate owns tasks end-to-end — implementation through PR creation and CI verification — while the TL stays free for user interaction.

**Core principle:** TL never implements. Teammates own PRs. Shepherd merges.

**Requires:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` enabled in settings.

**Announce at start:** "I'm using the team-driven-development skill to execute this plan with an agent team."

## When to Use

**Use when:**
- You have an implementation plan (from `superpowers:writing-plans` or equivalent)
- Tasks are parallelizable — teammates can work independently
- You want PR-based workflow with CI verification
- You want the TL free for discussion while work happens

**Don't use when:**
- Tasks are highly sequential with tight dependencies
- Single-file changes where subagent-driven-development is simpler
- Quick fixes that don't warrant team overhead

**vs. subagent-driven-development:** Subagents run within your session and report back. Agent teams are independent sessions that own their work end-to-end including PRs.

**vs. executing-plans:** Executing-plans is batch execution in a separate session. Team-driven is parallel execution across multiple sessions with PR-based integration.

## Prerequisites Check

Before starting, verify:

```bash
# 1. Agent teams enabled
# Check CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is set

# 2. GitHub CLI authenticated
gh auth status

# 3. Repo has pushable remote
git remote -v
```

If any prerequisite fails, tell the user what's missing and how to fix it.

## Phase 1: Setup

### 1.1 Pre-commit Hooks

**Safety check first:**
```bash
# Check for existing hooks
ls -la .git/hooks/pre-commit 2>/dev/null
# Check for managed hook systems
ls .husky/ .lefthook.yml .pre-commit-config.yaml 2>/dev/null
```

**If existing hooks found:** STOP. Show the user what's currently configured. Ask: "Pre-commit hooks already exist ({details}). Should I keep the existing setup, replace it, or merge my suggestions into it?"

**If no existing hooks:** Proceed with setup.

**Auto-detect always-on hooks by reading the repo:**

| Check for | What to set up |
|---|---|
| `package.json` scripts containing `lint` | Lint check using that exact script |
| `package.json` scripts containing `format` | Format check using that exact script |
| `Cargo.toml` | `cargo fmt --check && cargo clippy` |
| `pyproject.toml` with linter config | Linter using detected tool |
| Build script in `package.json`/`Makefile`/`Cargo.toml` | Build check |

Read `package.json` scripts, `Makefile` targets, and CI config (`.github/workflows/*.yml`) to find exact commands. Do NOT hardcode — use the project's actual commands.

**Plan-specific hooks:** Analyze the plan and CI config. Propose additional hooks as a checklist to the user. Examples:
- "CI runs `npm run test:unit` — add to pre-commit?"
- "CI checks types with `tsc --noEmit` — add to pre-commit?"
- "Plan adds API routes and CI runs integration tests — add to pre-commit?"

User picks which to include.

**Generate the hook:**

Write a `.git/hooks/pre-commit` shell script that runs each selected check sequentially, failing fast on first error. Make it executable. This is local-only — do NOT commit it to the repo.

**Apply to each worktree** after creation (copy the pre-commit hook to each worktree's `.git/hooks/`).

### 1.2 Create Worktrees

Follow `superpowers:using-git-worktrees` patterns:
- One worktree per teammate
- Each on its own branch: `team/{teammate-name}` or `team/task-{N}-{short-description}`
- Run project setup (dependency install) in each worktree
- Copy pre-commit hooks to each worktree
- Verify baseline tests pass in each worktree

### 1.3 Parse Plan into Task Groups

Read the plan file. Group tasks into clusters for teammates:
- Tasks that touch the same files or subsystem → same teammate
- Independent subsystems → different teammates
- Respect declared dependencies — dependent tasks go to same teammate when possible
- Aim for roughly equal work per teammate

Default: 1 teammate per task group, cap at 4-5 teammates. More than 5 has diminishing returns.

## Phase 2: Team Spawn

### 2.1 Spawn Teammates

For each task group, spawn a teammate agent:

- Use the prompt template at `skills/team-driven-development/teammate-prompt.md`
- Fill in all `{PLACEHOLDER}` values:
  - `{TEAMMATE_NAME}`: descriptive name (e.g., "auth-module", "api-endpoints")
  - `{WORKTREE_PATH}`: absolute path to their worktree
  - `{BRANCH_NAME}`: their branch name
  - `{TASK_TEXT}`: full text of their assigned tasks from the plan (copy verbatim — do NOT summarize)
  - `{PLAN_CONTEXT}`: relevant architecture/context sections from the plan header
  - `{PR_TITLE}`: suggested PR title
  - `{PR_SUMMARY}`: suggested PR summary
- **Require plan approval** before teammates implement — this gives the TL (and user) a chance to catch misunderstandings early

### 2.2 TL Goes Idle

After spawning all teammates:
- Announce to the user: "Team spawned: {N} teammates working on {task summary}. I'm free for discussion — ask me anything or I'll monitor progress."
- Enter monitoring mode — main loop stays free for user interaction

## Phase 3: Monitor

Stay in this loop until all teammates report PRs ready:

**On teammate status message:**
- PR created → acknowledge, note PR number
- CI green → acknowledge, add to "ready for merge" list
- Stuck → help debug: read their failure, suggest fixes, or redirect approach
- Question → answer with context from the plan or codebase

**On teammate death/hang:**
- If a teammate stops responding or errors out, spawn a replacement with the remaining tasks from that group
- Give the replacement the same worktree (or create a new one if corrupted)

**On user interaction:**
- User can brainstorm, ask questions, steer teammates, or request changes at any time
- TL answers directly — never delegates user interaction to teammates

**Progress tracking:**
- Keep a mental tally: which teammates are working, which have PRs, which are CI-green
- When asked for status, report: "{N}/{TOTAL} teammates done. PRs: {list with CI status}."

## Phase 4: Merge

When all teammates report PRs ready (or all possible PRs are ready and blocked ones are escalated):

### 4.1 Spawn PR Shepherd

- Use the prompt template at `skills/team-driven-development/pr-shepherd-prompt.md`
- Fill in:
  - `{REPO_PATH}`: repo root path
  - `{PLAN_FILE}`: path to the plan file
  - `{BASE_BRANCH}`: main or master
- The shepherd handles merge ordering, rebasing, and CI verification

### 4.2 Monitor Shepherd

- Shepherd messages TL with progress on each PR merge
- If shepherd escalates (CI failure, merge conflict, push failure): help resolve or ask user
- When shepherd reports done: proceed to Phase 5

## Phase 5: Cleanup

### 5.1 Verify Final State

```bash
# All PRs merged
gh pr list --state open

# CI green on main
gh run list --branch main --limit 1

# Main branch up to date
git checkout main && git pull
```

### 5.2 Clean Up

1. Shut down all teammate agents
2. Remove worktrees: `git worktree remove {path}` for each
3. Clean up the agent team
4. Use `superpowers:finishing-a-development-branch` for any remaining branch cleanup

### 5.3 Report Summary

```
## Team Execution Summary

**Plan:** {plan file}
**Teammates:** {N}

**PRs Merged:**
- PR #N: Title ✓
- PR #N: Title ✓

**Issues Encountered:**
- {any notable blockers or escalations}

**Final State:**
- main: {commit hash}
- CI: passing
```

## Quick Reference

| Phase | TL Does | Teammates Do | Shepherd Does |
|---|---|---|---|
| Setup | Hooks, worktrees, parse plan | — | — |
| Spawn | Spawn agents, assign tasks | Receive tasks, plan approach | — |
| Monitor | Answer questions, debug blockers | Implement, test, PR, fix CI | — |
| Merge | Resolve escalations | — | Rebase, verify CI, merge |
| Cleanup | Verify, remove worktrees, report | — | — |

## Red Flags

**TL should NEVER:**
- Implement tasks itself (delegate to teammates)
- Merge PRs directly (that's the shepherd's job)
- Force push anything
- Skip the pre-commit hooks setup
- Spawn more than 5 teammates without user consent
- Overwrite existing pre-commit hooks without asking

**Teammates should NEVER:**
- Work outside their worktree
- Push to main/master
- Merge their own PR
- Go idle with failing CI
- Skip TDD

**Shepherd should NEVER:**
- Force push
- Merge with failing CI
- Write feature code
- Reorder PRs breaking dependencies

## Integration

**Called after:**
- `superpowers:writing-plans` — as a third execution option alongside subagent-driven and executing-plans

**References:**
- `superpowers:using-git-worktrees` — worktree creation pattern
- `superpowers:test-driven-development` — teammates follow TDD
- `superpowers:verification-before-completion` — teammates verify before claiming ready
- `superpowers:finishing-a-development-branch` — final cleanup

**Hooks:**
- `TeammateIdle` — prevents teammates from idling before PR is ready
- `TaskCompleted` — verifies code is committed before task completion
