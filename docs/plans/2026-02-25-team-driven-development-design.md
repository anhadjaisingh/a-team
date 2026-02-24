# Team-Driven Development — Design Document

> **Plugin:** a-team (extension of superpowers)
> **Skill:** team-driven-development
> **Date:** 2026-02-25

## Goal

A Claude Code plugin that orchestrates a team of agents to execute an implementation plan in parallel, using Claude's built-in agent teams feature. Each teammate agent owns tasks end-to-end — from implementation through PR creation and CI verification — while the TL agent stays free for user interaction.

## Architecture

The plugin adds a third execution method alongside superpowers' existing `subagent-driven-development` and `executing-plans`. After `writing-plans` completes, the user invokes `/execute-team` (or the skill directly) to spawn an agent team that works through the plan in parallel.

The system has four agent roles:
- **TL (Team Lead):** The user's interactive session. Orchestrates, monitors, answers questions. Never implements.
- **Teammates:** Worker agents, each in their own git worktree. Implement tasks, create PRs, fix CI failures.
- **PR Shepherd:** On-demand agent spawned when PRs are ready. Rebases and merges PRs in dependency order.
- **User:** Interacts with the TL freely throughout — brainstorming, steering, debugging.

## Plugin Structure

```
a-team/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── team-driven-development/
│       ├── SKILL.md                # Main TL orchestration skill
│       ├── teammate-prompt.md      # Spawn prompt for worker teammates
│       └── pr-shepherd-prompt.md   # Spawn prompt for PR shepherd
├── commands/
│   └── execute-team.md             # /execute-team slash command
├── hooks/
│   ├── hooks.json                  # TeammateIdle + TaskCompleted hooks
│   ├── teammate-idle.sh            # TeammateIdle hook script
│   └── task-completed.sh           # TaskCompleted hook script
├── LICENSE
└── README.md
```

## TL Orchestration Flow

### Phase 1: Setup

1. **Verify prerequisites**
   - Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled
   - Verify `gh` CLI is authenticated
   - Verify repo has a remote and is pushable

2. **Pre-commit hooks**
   - **Safety check first:** If `.git/hooks/pre-commit` exists, or managed hook systems are detected (`.husky/`, `.lefthook.yml`, `.pre-commit-config.yaml`), stop and ask user for consent before modifying/overwriting.
   - **Always-on hooks** (auto-detected from repo):

     | Detected by | Hook |
     |---|---|
     | `package.json` with eslint/biome | Lint check |
     | `package.json` with prettier/biome | Format check |
     | `.rustfmt.toml` or `Cargo.toml` | `cargo fmt --check` |
     | `pyproject.toml` with ruff/flake8 | Linter run |
     | Any build system | Build check |

     TL reads `package.json` scripts, `Makefile` targets, CI config to find exact commands.

   - **Plan-specific hooks** (TL suggests, user confirms):
     TL analyzes the plan and CI config, proposes additional hooks as a checklist. User picks which to include.

   - **Implementation:** Native `.git/hooks/pre-commit` shell script. Not committed to repo (local-only). Runs checks sequentially, fails fast. Applied to each worktree after creation.

3. **Create worktrees**
   - One worktree per teammate, following `superpowers:using-git-worktrees` patterns
   - Each gets its own branch named after its task group

### Phase 2: Team Spawn

1. Parse plan into task groups (cluster related tasks per teammate)
2. Determine team size (default: 1 teammate per task group, cap ~4-5)
3. Spawn teammates with `teammate-prompt.md` — each gets: task group text, worktree path, branch name
4. Require plan approval before teammates implement
5. TL goes idle — main loop free for user interaction

### Phase 3: Monitor

TL stays in a monitoring loop:
- Receive teammate status messages (task done, PR created, CI status, stuck)
- Answer teammate questions
- If teammate stuck on CI failures: help debug or redirect
- If teammate dies/hangs: spawn replacement with remaining tasks
- User can brainstorm, discuss, or steer at any time

### Phase 4: Merge

When all teammates report PRs ready:
1. Spawn PR shepherd agent on-demand with `pr-shepherd-prompt.md`
2. Shepherd rebases PRs in dependency order
3. Shepherd merges each PR after CI passes
4. If rebase causes failures: shepherd fixes or escalates to TL
5. Shepherd reports final status

### Phase 5: Cleanup

1. Verify all PRs merged, all CI green on main
2. Clean up worktrees
3. Clean up the agent team
4. Report summary to user

## Teammate Agent Design

Each teammate is spawned with `teammate-prompt.md` injected as the spawn prompt.

**Workflow per task:**
1. Follow TDD (`superpowers:test-driven-development`)
2. Commit frequently with clear messages
3. When task group complete: push branch, create PR via `gh pr create`
4. PR body includes: summary, what was implemented, test plan with evidence
5. Watch CI — poll `gh pr checks`
6. If CI fails: read failure, fix, push, re-check. Loop until green.
7. If stuck after 3 attempts on same CI failure: message TL with details and what was tried

**Constraints:**
- Never work outside assigned worktree
- Never push to main/master directly
- Never merge own PR
- If dependency on another teammate's work: message them, don't access their worktree
- Run pre-commit hooks before pushing

**Communication protocol:**
- Message TL when: PR created, CI green and ready, stuck on blocker, question about requirements
- Message teammate when: need their output, dependency question
- Keep messages concise — what you need and why

## PR Shepherd Agent Design

Spawned on-demand by TL with `pr-shepherd-prompt.md`.

**Workflow:**
1. List open PRs via `gh pr list`
2. Read plan for task dependency ordering
3. Build merge queue: independent PRs first, dependent PRs after dependencies land
4. For each PR in order:
   - `git checkout <pr-branch>`
   - `git pull` (get latest from teammate)
   - `git rebase main`
   - `git push` (regular push — should work since teammate is done)
   - If push fails: `git pull --rebase && git push` (one retry)
   - If still fails: escalate to TL
   - Wait for CI: poll `gh pr checks`
   - If CI fails after rebase: attempt fix (max 2 tries), then escalate to TL
   - If CI passes: merge via `gh pr merge --squash`
   - Confirm merge landed on main
5. Report final summary to TL

**Constraints:**
- Never force push — if regular push doesn't work after one pull-rebase-push retry, escalate
- Never merge a PR with failing CI
- Never reorder PRs breaking declared dependencies
- If merge conflict isn't trivially resolvable: escalate to TL

## Hooks Integration

**`TeammateIdle` hook:**
When teammate is about to go idle, checks:
- Did teammate create a PR?
- If PR exists, is CI passing?
- If CI failing: exit code 2, feedback to fix CI before going idle
- If no PR but tasks were assigned: exit code 2, feedback to create PR

**`TaskCompleted` hook:**
When task marked complete, verifies:
- Task's code was committed
- If last task in teammate's group: remind to create PR

## Integration with Superpowers

**Entry point:** `/execute-team` slash command, or direct skill invocation after `writing-plans`

**Skills referenced:**
- `superpowers:using-git-worktrees` — worktree creation pattern
- `superpowers:test-driven-development` — teammates follow TDD
- `superpowers:verification-before-completion` — teammates verify before claiming ready
- `superpowers:finishing-a-development-branch` — final cleanup after all PRs merged

## Packaging

- Lives in `a-team` repo as a Claude Code plugin (`.claude-plugin/plugin.json`)
- Designed to work alongside superpowers (references its skills but functions independently)
- Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` enabled
- Battle-test in a-team, upstream to superpowers later
