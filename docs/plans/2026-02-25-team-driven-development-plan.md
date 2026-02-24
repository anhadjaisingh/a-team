# Team-Driven Development Plugin — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Claude Code plugin that orchestrates agent teams to execute implementation plans in parallel, with teammates owning PRs end-to-end and a PR shepherd handling merge ordering.

**Architecture:** A plugin with one main skill (TL orchestration), two prompt templates (teammate, PR shepherd), one slash command, and two hook scripts. The skill integrates with superpowers as a third execution method alongside subagent-driven-development and executing-plans.

**Tech Stack:** Markdown (skills/prompts), shell scripts (hooks), JSON (plugin manifest/hook config)

---

### Task 1: Plugin Manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

**Step 1: Write the plugin manifest**

```json
{
  "name": "a-team",
  "description": "Team-driven development: orchestrate Claude Code agent teams to execute plans in parallel with PR-based workflows",
  "version": "0.1.0",
  "author": {
    "name": "Anhad Jai Singh"
  },
  "repository": "https://github.com/anhadjaisingh/a-team",
  "license": "MIT",
  "keywords": ["agent-teams", "orchestration", "parallel-development", "pr-workflow"]
}
```

**Step 2: Verify plugin structure is valid**

Run: `cat .claude-plugin/plugin.json | python3 -m json.tool`
Expected: Valid JSON output, no errors

**Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add plugin manifest for a-team"
```

---

### Task 2: Teammate Prompt Template

**Files:**
- Create: `skills/team-driven-development/teammate-prompt.md`

**Step 1: Write the teammate prompt template**

This is the spawn prompt injected into each teammate agent. It uses `{PLACEHOLDER}` syntax for values the TL fills in at spawn time.

```markdown
# Teammate Agent — {TEAMMATE_NAME}

You are a teammate agent on a development team. Your job is to implement your assigned tasks, create a PR, and ensure CI passes before going idle.

## Your Assignment

**Worktree:** `{WORKTREE_PATH}`
**Branch:** `{BRANCH_NAME}`
**Tasks:**

{TASK_TEXT}

## Plan Context

{PLAN_CONTEXT}

## Workflow

Follow this workflow for each task:

### 1. Implement with TDD

Follow `superpowers:test-driven-development` strictly:
- Write the failing test first
- Watch it fail
- Write minimal code to pass
- Watch it pass
- Refactor if needed
- Commit after each red-green-refactor cycle

### 2. Commit Frequently

Each commit should be a logical unit:
- One failing test + its implementation = one commit
- Use clear commit messages: `feat:`, `fix:`, `test:`, `refactor:`

### 3. Run Pre-commit Hooks

Before pushing, ensure pre-commit hooks pass. They are configured to catch issues that would fail CI. If hooks fail:
- Read the error output carefully
- Fix the issue
- Re-run until hooks pass

### 4. Create PR When Task Group Is Complete

Once all your assigned tasks are implemented and committed:

```bash
git push -u origin {BRANCH_NAME}
gh pr create --title "{PR_TITLE}" --body "$(cat <<'PREOF'
## Summary
{PR_SUMMARY}

## What was implemented
- [List each task completed]

## Test plan
- [For each major piece, describe how it was tested]
- [Include command output or screenshots as evidence]
- [List any manual verification steps performed]

🤖 Generated with [Claude Code](https://claude.com/claude-code) (agent team)
PREOF
)"
```

### 5. Watch CI and Fix Failures

After creating the PR:

```bash
# Poll CI status
gh pr checks {PR_NUMBER} --watch
```

If CI fails:
1. Read the failure output: `gh pr checks {PR_NUMBER}` then inspect the failing check
2. Identify the root cause — don't guess
3. Fix the issue, commit, push
4. Re-check CI
5. **If stuck after 3 attempts on the same failure:** message the TL with:
   - What check is failing
   - The error output
   - What you've tried so far
   - Your best guess at the root cause

### 6. Report Status

Message the TL when:
- **PR created:** "PR #{NUMBER} created: {TITLE}. CI running."
- **CI green:** "PR #{NUMBER} CI passing. Ready for merge."
- **Stuck:** "PR #{NUMBER} blocked: {DESCRIPTION}. Tried: {ATTEMPTS}. Need help with: {SPECIFIC_ASK}."
- **Question:** "Question about {TASK}: {SPECIFIC_QUESTION}"

Message another teammate when:
- You need output from their work
- You have a dependency question
- Keep it concise — what you need and why

## Constraints

- **Never** work outside your worktree (`{WORKTREE_PATH}`)
- **Never** push to main/master directly
- **Never** merge your own PR — the PR shepherd handles merging
- **Never** access another teammate's worktree — message them instead
- **Always** run pre-commit hooks before pushing
- **Always** follow `superpowers:verification-before-completion` before claiming work is done
```

**Step 2: Verify the template renders correctly**

Run: `wc -l skills/team-driven-development/teammate-prompt.md`
Expected: File exists with content (~90-100 lines)

**Step 3: Commit**

```bash
git add skills/team-driven-development/teammate-prompt.md
git commit -m "feat: add teammate agent spawn prompt template"
```

---

### Task 3: PR Shepherd Prompt Template

**Files:**
- Create: `skills/team-driven-development/pr-shepherd-prompt.md`

**Step 1: Write the PR shepherd prompt template**

```markdown
# PR Shepherd Agent

You are the PR shepherd. Your sole job is to merge all teammate PRs into main in the correct dependency order. You do not write features. You only rebase, verify, and merge.

## Context

**Repository:** `{REPO_PATH}`
**Plan file:** `{PLAN_FILE}`
**Target branch:** `{BASE_BRANCH}`

## Workflow

### 1. Survey Open PRs

```bash
gh pr list --state open --json number,title,headRefName,statusCheckRollup
```

### 2. Determine Merge Order

Read the plan file to understand task dependency ordering. Build a merge queue:
- Independent PRs first (no dependencies on other PRs)
- Dependent PRs after their dependencies have landed
- If two PRs are independent of each other, merge in plan task order

### 3. Merge Each PR in Order

For each PR in the queue:

**Step A: Checkout and rebase**
```bash
gh pr checkout {PR_NUMBER}
git pull
git rebase {BASE_BRANCH}
```

**Step B: Push**
```bash
git push
```

If push fails:
```bash
git pull --rebase
git push
```

If push still fails: **STOP. Escalate to TL.** Something is wrong — do not force push.

**Step C: Wait for CI**
```bash
gh pr checks {PR_NUMBER} --watch
```

If CI fails after rebase:
1. Read the failure carefully
2. Attempt to fix (the rebase may have introduced a conflict with recently merged code)
3. Commit, push, re-check CI
4. **Max 2 fix attempts.** If still failing: message TL with the failure details and move on to the next independent PR in the queue

**Step D: Merge**
```bash
gh pr merge {PR_NUMBER} --squash --delete-branch
```

Verify merge landed:
```bash
git checkout {BASE_BRANCH}
git pull
git log --oneline -1
```

### 4. Report Summary

After processing all PRs, message the TL with:

```
## PR Shepherd Summary

**Merged:**
- PR #N: Title (merged successfully)
- PR #N: Title (merged successfully)

**Blocked (escalated to TL):**
- PR #N: Title — Reason: {why it couldn't be merged}

**Final state:**
- main branch: {latest commit hash}
- CI status on main: {passing/failing}
```

## Constraints

- **Never** force push — if regular push doesn't work after one pull-rebase-push retry, escalate
- **Never** merge a PR with failing CI — escalate to TL instead
- **Never** reorder PRs in a way that breaks declared dependencies
- **Never** write feature code — you only rebase, fix rebase conflicts, and merge
- If merge conflict isn't trivially resolvable (e.g., requires understanding feature intent): escalate to TL
- If you detect a dependency cycle in the PRs: escalate to TL immediately
```

**Step 2: Verify the template renders correctly**

Run: `wc -l skills/team-driven-development/pr-shepherd-prompt.md`
Expected: File exists with content (~80-90 lines)

**Step 3: Commit**

```bash
git add skills/team-driven-development/pr-shepherd-prompt.md
git commit -m "feat: add PR shepherd agent spawn prompt template"
```

---

### Task 4: Hook Scripts

**Files:**
- Create: `hooks/teammate-idle.sh`
- Create: `hooks/task-completed.sh`
- Create: `hooks/hooks.json`

**Step 1: Write the TeammateIdle hook script**

```bash
#!/usr/bin/env bash
# TeammateIdle hook — prevents teammates from going idle before their PR is ready
# Exit code 0: allow idle
# Exit code 2: send feedback, keep teammate working

set -euo pipefail

# Get the teammate's current branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  # Not on a feature branch — allow idle
  exit 0
fi

# Check if a PR exists for this branch
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -z "$PR_NUMBER" ]; then
  # No PR created yet — check if there are unpushed commits
  UNPUSHED=$(git log --oneline "origin/${BRANCH}..HEAD" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$UNPUSHED" -gt 0 ] 2>/dev/null; then
    echo "You have $UNPUSHED unpushed commits but haven't created a PR yet. Push your branch and create a PR before going idle."
    exit 2
  fi

  # Check if branch has commits ahead of base
  BASE_BRANCH=$(git rev-parse --abbrev-ref "$(git config --get "branch.${BRANCH}.merge" 2>/dev/null || echo "origin/main")" 2>/dev/null || echo "main")
  AHEAD=$(git rev-list --count "${BASE_BRANCH}..HEAD" 2>/dev/null || echo "0")
  if [ "$AHEAD" -gt 0 ]; then
    echo "Your branch has $AHEAD commits but no PR. Push your branch and create a PR before going idle."
    exit 2
  fi

  # No commits, no PR — teammate may legitimately be done or hasn't started
  exit 0
fi

# PR exists — check CI status
CI_STATUS=$(gh pr checks "$PR_NUMBER" --json bucket --jq '[.[] | .bucket] | if any(. == "fail") then "failing" elif any(. == "pending") then "pending" else "passing" end' 2>/dev/null || echo "unknown")

case "$CI_STATUS" in
  failing)
    echo "CI is failing on PR #${PR_NUMBER}. Check 'gh pr checks ${PR_NUMBER}' and fix the failures before going idle."
    exit 2
    ;;
  pending)
    echo "CI is still running on PR #${PR_NUMBER}. Wait for checks to complete and verify they pass before going idle."
    exit 2
    ;;
  passing)
    # All good — teammate can go idle
    exit 0
    ;;
  *)
    # Unknown state — allow idle but warn
    exit 0
    ;;
esac
```

**Step 2: Write the TaskCompleted hook script**

```bash
#!/usr/bin/env bash
# TaskCompleted hook — verifies task work was committed before marking complete
# Exit code 0: allow completion
# Exit code 2: send feedback, prevent completion

set -euo pipefail

# Check for uncommitted changes
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ "$UNCOMMITTED" -gt 0 ]; then
  echo "You have $UNCOMMITTED uncommitted files. Commit your work before marking the task as complete."
  echo ""
  git status --short
  exit 2
fi

# All clear
exit 0
```

**Step 3: Write the hooks.json config**

```json
{
  "hooks": {
    "TeammateIdle": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/teammate-idle.sh'",
            "async": false
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/task-completed.sh'",
            "async": false
          }
        ]
      }
    ]
  }
}
```

**Step 4: Make hook scripts executable**

Run: `chmod +x hooks/teammate-idle.sh hooks/task-completed.sh`

**Step 5: Verify scripts parse correctly**

Run: `bash -n hooks/teammate-idle.sh && bash -n hooks/task-completed.sh && echo "OK"`
Expected: `OK` (no syntax errors)

**Step 6: Verify hooks.json is valid JSON**

Run: `cat hooks/hooks.json | python3 -m json.tool > /dev/null && echo "OK"`
Expected: `OK`

**Step 7: Commit**

```bash
git add hooks/
git commit -m "feat: add TeammateIdle and TaskCompleted hook scripts"
```

---

### Task 5: Main Skill — SKILL.md

**Files:**
- Create: `skills/team-driven-development/SKILL.md`

**Step 1: Write the main TL orchestration skill**

```markdown
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
**Duration:** {approximate time}
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
```

**Step 2: Verify skill file exists and has frontmatter**

Run: `head -5 skills/team-driven-development/SKILL.md`
Expected: Shows YAML frontmatter with `name: team-driven-development`

**Step 3: Commit**

```bash
git add skills/team-driven-development/SKILL.md
git commit -m "feat: add main team-driven-development skill"
```

---

### Task 6: Slash Command

**Files:**
- Create: `commands/execute-team.md`

**Step 1: Write the slash command**

```markdown
---
description: "Execute an implementation plan using a parallel agent team. Each teammate owns tasks end-to-end including PRs and CI verification."
disable-model-invocation: true
---

Invoke the a-team:team-driven-development skill and follow it exactly as presented to you.

If the user provided a plan file path as an argument, use that. Otherwise, find the most recent plan file in `docs/plans/` by modification date.
```

**Step 2: Verify file exists**

Run: `cat commands/execute-team.md`
Expected: Shows frontmatter and invocation instruction

**Step 3: Commit**

```bash
git add commands/execute-team.md
git commit -m "feat: add /execute-team slash command"
```

---

### Task 7: Final Verification and Cleanup

**Step 1: Verify complete plugin structure**

Run: `find . -not -path './.git/*' -not -path './.git' | sort`

Expected:
```
.
./.claude-plugin
./.claude-plugin/plugin.json
./LICENSE
./commands
./commands/execute-team.md
./docs
./docs/plans
./docs/plans/2026-02-25-team-driven-development-design.md
./docs/plans/2026-02-25-team-driven-development-plan.md
./hooks
./hooks/hooks.json
./hooks/task-completed.sh
./hooks/teammate-idle.sh
./skills
./skills/team-driven-development
./skills/team-driven-development/SKILL.md
./skills/team-driven-development/pr-shepherd-prompt.md
./skills/team-driven-development/teammate-prompt.md
```

**Step 2: Verify all JSON files are valid**

Run: `for f in .claude-plugin/plugin.json hooks/hooks.json; do echo "Checking $f..." && python3 -m json.tool "$f" > /dev/null && echo "OK"; done`
Expected: Both files OK

**Step 3: Verify all shell scripts have no syntax errors**

Run: `for f in hooks/*.sh; do echo "Checking $f..." && bash -n "$f" && echo "OK"; done`
Expected: Both scripts OK

**Step 4: Verify all markdown files exist and have content**

Run: `for f in skills/team-driven-development/SKILL.md skills/team-driven-development/teammate-prompt.md skills/team-driven-development/pr-shepherd-prompt.md commands/execute-team.md; do echo "$f: $(wc -l < "$f") lines"; done`
Expected: All files exist with reasonable line counts

**Step 5: Final commit (plan file)**

```bash
git add docs/plans/2026-02-25-team-driven-development-plan.md
git commit -m "docs: add implementation plan for team-driven-development"
```
